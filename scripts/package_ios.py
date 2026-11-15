#!/usr/bin/env python3
"""Package the unsigned device archive on macOS; inspect IPA files on any host."""

import argparse
import hashlib
import os
import plistlib
import re
import shutil
import stat
import struct
import subprocess
import sys
import tempfile
import zipfile
from pathlib import Path, PurePosixPath


BUNDLE_ID = "io.github.caolib.kira"
MINIMUM_OS = (14, 0, 0)
VERSION_PATTERN = r"(?P<name>[0-9]+\.[0-9]+\.[0-9]+)(?:-[0-9A-Za-z.-]+)?\+(?P<build>[0-9]+)"
IPA_PATTERN = re.compile(rf"kira-(?P<version>{VERSION_PATTERN})-ios-unsigned\.ipa")
CPU_TYPE_ARM64 = 0x0100000C
LC_BUILD_VERSION = 0x32
LC_CODE_SIGNATURE = 0x1D
CSMAGIC_CODEDIRECTORY = 0xFADE0C02
CSMAGIC_EMBEDDED_SIGNATURE = 0xFADE0CC0
CSMAGIC_BLOBWRAPPER = 0xFADE0B01
CS_ADHOC = 0x2
CODE_DIRECTORY_HEADERS = {0x20000: 44, 0x20001: 44, 0x20100: 48, 0x20200: 52,
                          0x20300: 64, 0x20400: 88, 0x20500: 96, 0x20600: 108}
MACHO_MAGICS = {
    b"\xcf\xfa\xed\xfe": "<",
    b"\xfe\xed\xfa\xcf": ">",
}
FAT_MAGICS = {
    b"\xca\xfe\xba\xbe": (">", False),
    b"\xbe\xba\xfe\xca": ("<", False),
    b"\xca\xfe\xba\xbf": (">", True),
    b"\xbf\xba\xfe\xca": ("<", True),
}


def require(condition, message):
    if not condition:
        raise ValueError(message)


def version_parts(version):
    match = re.fullmatch(VERSION_PATTERN, version)
    require(match is not None, f"Expected a full pubspec version with numeric build: {version}")
    return match.group("name"), match.group("build")


def pubspec_version(path):
    text = Path(path).read_text(encoding="utf-8-sig")
    matches = re.findall(r"(?m)^version:\s*([^\r\n#]+)", text)
    require(len(matches) == 1, "pubspec.yaml must contain exactly one version")
    version = matches[0].strip().strip("\"'")
    version_parts(version)
    return version


def os_version(value):
    require(isinstance(value, str) and re.fullmatch(r"[0-9]+(?:\.[0-9]+){0,2}", value),
            f"Invalid OS version: {value}")
    parts = tuple(int(part) for part in value.split("."))
    return parts + (0,) * (3 - len(parts))


def packed_version(value):
    return value >> 16, (value >> 8) & 0xFF, value & 0xFF


def validate_adhoc_directory(blob, image, signature_offset, label):
    # Layout/constants follow Apple's xnu/osfmk/kern/cs_blobs.h (big-endian blobs).
    require(len(blob) >= 44, f"Truncated CodeDirectory: {label}")
    magic, length, version, flags, hash_offset, ident_offset, special_count, code_count, code_limit = struct.unpack_from(
        ">9I", blob)
    require(magic == CSMAGIC_CODEDIRECTORY and length == len(blob), f"Invalid CodeDirectory: {label}")
    header = CODE_DIRECTORY_HEADERS.get(version)
    require(header is not None and len(blob) >= header, f"Unknown/truncated CodeDirectory version: {label}")
    require(flags & CS_ADHOC, f"Runner has an identity signature, not ad-hoc: {label}")
    hash_size, hash_type, _, page_bits = struct.unpack_from(">4B", blob, 36)
    expected_sizes = {1: 20, 2: 32, 3: 20, 4: 48}
    require(expected_sizes.get(hash_type) == hash_size and page_bits <= 30,
            f"Unsupported CodeDirectory hash/page format: {label}")
    require(struct.unpack_from(">I", blob, 40)[0] == 0, f"Invalid CodeDirectory spare field: {label}")
    if version >= 0x20100:
        require(struct.unpack_from(">I", blob, 44)[0] == 0,
                f"Scatter CodeDirectory cannot be confirmed as linker ad-hoc: {label}")
    if version >= 0x20200:
        team_offset = struct.unpack_from(">I", blob, 48)[0]
        require(team_offset == 0, f"Runner ad-hoc signature must not declare an Apple team: {label}")
    if version >= 0x20300:
        spare, limit64 = struct.unpack_from(">IQ", blob, 52)
        require(spare == 0, f"Invalid CodeDirectory spare field: {label}")
        if limit64:
            code_limit = limit64
    if version >= 0x20500:
        require(struct.unpack_from(">I", blob, 92)[0] == 0,
                f"Pre-encrypted CodeDirectory cannot be confirmed as linker ad-hoc: {label}")
    if version >= 0x20600:
        require(struct.unpack_from(">II", blob, 100) == (0, 0),
                f"Linked CodeDirectory cannot be confirmed as linker ad-hoc: {label}")
    require(code_limit == signature_offset and code_limit > 0, f"Invalid CodeDirectory image bounds: {label}")
    page_size = 1 << page_bits if page_bits else code_limit
    require(code_count == (code_limit + page_size - 1) // page_size,
            f"Invalid CodeDirectory code-slot count: {label}")
    hashes_start = hash_offset - special_count * hash_size
    require(header <= ident_offset < hashes_start <= hash_offset
            and hash_offset + code_count * hash_size <= len(blob), f"Invalid CodeDirectory hash/string bounds: {label}")
    identifier_end = blob.find(b"\0", ident_offset, hashes_start)
    require(identifier_end > ident_offset and hash_offset + code_count * hash_size == len(blob),
            f"Invalid CodeDirectory identifier/trailing bounds: {label}")
    algorithm = {1: "sha1", 2: "sha256", 3: "sha256", 4: "sha384"}[hash_type]
    for index in range(code_count):
        expected = hashlib.new(algorithm, image[index * page_size:min((index + 1) * page_size, code_limit)]).digest()[:hash_size]
        actual = blob[hash_offset + index * hash_size:hash_offset + (index + 1) * hash_size]
        require(actual == expected, f"Invalid ad-hoc CodeDirectory page hash: {label}")


def validate_adhoc_signature(data, signature_offset, label):
    require(len(data) >= 12 and signature_offset < len(data), f"Truncated embedded signature: {label}")
    magic, length, count = struct.unpack_from(">3I", data, signature_offset)
    available = len(data) - signature_offset
    require(magic == CSMAGIC_EMBEDDED_SIGNATURE and 12 <= length <= available
            and 0 < count <= 32 and 12 + count * 8 <= length, f"Unknown/malformed embedded signature: {label}")
    blob = data[signature_offset:signature_offset + length]
    slots, ranges, directories = set(), [], []
    allowed = {2: 0xFADE0C01, 5: 0xFADE7171, 7: 0xFADE7172}
    for index in range(count):
        slot, offset = struct.unpack_from(">II", blob, 12 + index * 8)
        require(slot not in slots and 12 + count * 8 <= offset <= length - 8,
                f"Invalid embedded signature index: {label}")
        slots.add(slot)
        child_magic, child_length = struct.unpack_from(">II", blob, offset)
        require(child_length >= 8 and offset + child_length <= length
                and not any(offset < end and start < offset + child_length for start, end in ranges),
                f"Invalid embedded signature blob bounds: {label}")
        ranges.append((offset, offset + child_length))
        require(slot != 0x10000 and child_magic != CSMAGIC_BLOBWRAPPER,
                f"Runner has a CMS/Apple identity signature: {label}")
        child = blob[offset:offset + child_length]
        if slot == 0 or 0x1000 <= slot < 0x1005:
            require(child_magic == CSMAGIC_CODEDIRECTORY, f"Invalid CodeDirectory slot: {label}")
            directories.append(child)
        else:
            require(allowed.get(slot) == child_magic, f"Unknown embedded signature slot: {label}")
    require(0 in slots and directories, f"Missing primary CodeDirectory: {label}")
    end = 12 + count * 8
    for start, following_end in sorted(ranges):
        require(not any(blob[end:start]), f"Unindexed embedded signature data: {label}")
        end = following_end
    require(not any(blob[end:]) and not any(data[signature_offset + length:]),
            f"Unknown embedded signature trailing data: {label}")
    for directory in directories:
        validate_adhoc_directory(directory, data, signature_offset, label)


def macho_slices(data, label):
    """Read bounded Mach-O load commands, including every slice of a fat binary."""
    require(len(data) >= 4, f"Missing Mach-O data: {label}")
    magic = data[:4]
    if magic in FAT_MAGICS:
        endian, is_64 = FAT_MAGICS[magic]
        require(len(data) >= 8, f"Truncated fat Mach-O: {label}")
        count = struct.unpack_from(endian + "I", data, 4)[0]
        entry_size = 32 if is_64 else 20
        require(0 < count <= 32 and 8 + count * entry_size <= len(data),
                f"Invalid fat Mach-O table: {label}")
        result, ranges = [], []
        for index in range(count):
            fmt = endian + ("IIQQII" if is_64 else "IIIII")
            values = struct.unpack_from(fmt, data, 8 + index * entry_size)
            cpu, subtype, offset, size = values[:4]
            require(size >= 32 and offset >= 8 + count * entry_size and offset + size <= len(data),
                    f"Invalid fat Mach-O slice bounds: {label}")
            require(not any(offset < end and start < offset + size for start, end in ranges),
                    f"Overlapping fat Mach-O slices: {label}")
            ranges.append((offset, offset + size))
            require(data[offset:offset + 4] in MACHO_MAGICS, f"Invalid fat Mach-O slice: {label}")
            slices = macho_slices(data[offset:offset + size], label)
            require(len(slices) == 1 and slices[0]["cpu"] == cpu and slices[0]["subtype"] == subtype,
                    f"Fat Mach-O architecture mismatch: {label}")
            result.extend(slices)
        return result
    require(magic in MACHO_MAGICS, f"Expected a 64-bit Mach-O executable: {label}")
    require(len(data) >= 32, f"Truncated Mach-O header: {label}")
    endian = MACHO_MAGICS[magic]
    _, cpu, subtype, filetype, count, command_size, _, _ = struct.unpack_from(endian + "8I", data)
    require(count <= 65536 and 32 + command_size <= len(data), f"Invalid Mach-O load commands: {label}")
    position, platforms, min_versions, signatures = 32, [], [], []
    for _ in range(count):
        require(position + 8 <= 32 + command_size, f"Truncated Mach-O command: {label}")
        command, size = struct.unpack_from(endian + "II", data, position)
        require(size >= 8 and size % 4 == 0 and position + size <= 32 + command_size,
                f"Invalid Mach-O command size: {label}")
        if command == LC_BUILD_VERSION:
            require(size >= 24, f"Truncated LC_BUILD_VERSION: {label}")
            platform, minimum, _, tools = struct.unpack_from(endian + "4I", data, position + 8)
            require(24 + tools * 8 <= size, f"Invalid LC_BUILD_VERSION tools: {label}")
            platforms.append(platform)
            min_versions.append(packed_version(minimum))
        if command == LC_CODE_SIGNATURE:
            require(size == 16, f"Malformed LC_CODE_SIGNATURE: {label}")
            offset, signature_size = struct.unpack_from(endian + "II", data, position + 8)
            require(offset >= 32 + command_size and signature_size >= 12 and offset + signature_size <= len(data),
                    f"Invalid LC_CODE_SIGNATURE bounds: {label}")
            signatures.append((offset, signature_size))
        position += size
    require(position == 32 + command_size, f"Mach-O load command size mismatch: {label}")
    require(len(signatures) <= 1, f"Multiple LC_CODE_SIGNATURE commands: {label}")
    return [{"cpu": cpu, "subtype": subtype, "filetype": filetype, "platforms": platforms,
             "minimums": min_versions, "signatures": signatures, "image": data}]


def device_macho(data, label, filetype, minimum, unsigned_main=False):
    slices = macho_slices(data, label)
    for item in slices:
        require(item["cpu"] == CPU_TYPE_ARM64, f"Expected device arm64, not another architecture: {label}")
        require(item["filetype"] == filetype, f"Unexpected Mach-O file type: {label}")
        # An arm64 simulator binary also passes lipo; platform 2 is actual iOS, 7 is simulator.
        require(item["platforms"] == [2], f"Expected LC_BUILD_VERSION device iOS platform (2): {label}")
        require(all(value <= minimum for value in item["minimums"]),
                f"Binary requires an OS newer than the app minimum: {label}")
        if unsigned_main and item["signatures"]:
            offset, size = item["signatures"][0]
            validate_adhoc_signature(item["image"][:offset + size], offset, label)
    return slices


class DirectoryBundle:
    def __init__(self, app):
        self.app = Path(app).resolve()
        require(self.app.is_dir() and self.app.name == "Runner.app", "Missing archive Runner.app")
        self.paths = {path.relative_to(self.app).as_posix(): path for path in self.app.rglob("*")}
        for name, path in self.paths.items():
            require(path.is_symlink() or path.is_dir() or path.is_file(), f"Unsupported bundle entry: {name}")
            if path.is_symlink():
                target = os.readlink(path)
                require(not os.path.isabs(target), f"Absolute bundle symlink: {name}")
                try:
                    resolved = path.resolve(strict=True)
                except (OSError, RuntimeError) as error:
                    raise ValueError(f"Broken or cyclic bundle symlink: {name}") from error
                require(resolved.is_relative_to(self.app), f"Bundle symlink escapes Runner.app: {name}")

    def has(self, name):
        return name in self.paths

    def read(self, name):
        path = self.paths.get(name)
        require(path is not None and path.is_file(), f"Missing bundle file: {name}")
        return path.read_bytes()

    def mode(self, name):
        require(name in self.paths, f"Missing bundle entry: {name}")
        return self.paths[name].stat().st_mode

    def inventory(self):
        result = {}
        for name, path in self.paths.items():
            mode = path.lstat().st_mode
            if stat.S_ISLNK(mode):
                result[name] = ("link", os.readlink(path).encode("utf-8"))
            elif stat.S_ISREG(mode):
                result[name] = ("file", stat.S_IMODE(mode), hashlib.sha256(path.read_bytes()).hexdigest())
            else:
                result[name] = ("directory",)
        return result


class ZipBundle:
    def __init__(self, archive):
        self.archive = archive
        self.entries = {}
        prefix = "Payload/Runner.app/"
        names = set()
        for entry in archive.infolist():
            name = entry.filename
            require(name not in names, f"Duplicate IPA entry: {name}")
            names.add(name)
            path = PurePosixPath(name)
            require(name and not name.startswith("/") and "\\" not in name and "\x00" not in name
                    and all(part not in ("", ".", "..") for part in name.rstrip("/").split("/")),
                    f"Unsafe IPA entry: {name}")
            require(not entry.flag_bits & 1, "Encrypted IPA entries are not supported")
            if path.parts[0] == "__MACOSX":
                metadata_mode = entry.external_attr >> 16
                require(not stat.S_ISLNK(metadata_mode), "AppleDouble metadata must not contain symlinks")
                continue  # ditto's AppleDouble metadata; never treated as application content.
            if name in ("Payload/", "Payload/Runner.app/"):
                require(stat.S_ISDIR(entry.external_attr >> 16), f"IPA root is not a directory: {name}")
                continue
            require(name.startswith(prefix), f"Unexpected IPA payload: {name}")
            relative = name[len(prefix):].rstrip("/")
            require(relative and relative not in self.entries, f"Duplicate IPA bundle path: {name}")
            mode = entry.external_attr >> 16
            require(stat.S_ISREG(mode) or stat.S_ISDIR(mode) or stat.S_ISLNK(mode),
                    f"IPA entry lacks Unix file metadata: {name}")
            require(entry.is_dir() == stat.S_ISDIR(mode), f"Inconsistent IPA directory metadata: {name}")
            self.entries[relative] = entry
        require(self.entries, "IPA does not contain Payload/Runner.app")
        for name, entry in self.entries.items():
            for parent in PurePosixPath(name).parents:
                parent_entry = self.entries.get(parent.as_posix())
                require(parent_entry is None or stat.S_ISDIR(parent_entry.external_attr >> 16),
                        f"IPA child is stored under a file or symlink: {name}")
            if stat.S_ISLNK(entry.external_attr >> 16):
                self.resolve(name)

    def resolve(self, name, seen=None):
        seen = set() if seen is None else seen
        require(name not in seen and len(seen) < 64, f"Cyclic IPA symlink: {name}")
        components = list(PurePosixPath(name).parts)
        for index in range(1, len(components) + 1):
            prefix = "/".join(components[:index])
            entry = self.entries.get(prefix)
            if entry is None or not stat.S_ISLNK(entry.external_attr >> 16):
                continue
            seen.add(name)
            target = self.archive.read(entry).decode("utf-8")
            require(target and not target.startswith("/") and "\\" not in target and "\x00" not in target,
                    f"Unsafe IPA symlink: {prefix}")
            parts = components[:index - 1]
            for part in target.split("/"):
                if part == "..":
                    require(parts, f"IPA symlink escapes Runner.app: {prefix}")
                    parts.pop()
                elif part not in ("", "."):
                    parts.append(part)
            parts.extend(components[index:])
            return self.resolve("/".join(parts), seen)
        require(name in self.entries, f"Missing IPA symlink target: {name}")
        return name

    def has(self, name):
        try:
            self.resolve(name)
        except ValueError:
            return False
        return True

    def read(self, name):
        entry = self.entries[self.resolve(name)]
        require(stat.S_ISREG(entry.external_attr >> 16), f"Expected a bundle file: {name}")
        return self.archive.read(entry)

    def mode(self, name):
        return self.entries[self.resolve(name)].external_attr >> 16

    @property
    def paths(self):
        return self.entries

    def inventory(self):
        result = {}
        for name, entry in self.entries.items():
            mode = entry.external_attr >> 16
            if stat.S_ISLNK(mode):
                result[name] = ("link", self.archive.read(entry))
            elif stat.S_ISREG(mode):
                result[name] = ("file", stat.S_IMODE(mode), hashlib.sha256(self.archive.read(entry)).hexdigest())
            else:
                result[name] = ("directory",)
        return result


def read_plist(bundle, name):
    try:
        value = plistlib.loads(bundle.read(name))
    except (plistlib.InvalidFileException, ValueError, TypeError) as error:
        raise ValueError(f"Invalid bundle plist: {name}") from error
    require(isinstance(value, dict), f"Expected a plist dictionary: {name}")
    return value


def validate_bundle(bundle, version):
    short_version, build_number = version_parts(version)
    info = read_plist(bundle, "Info.plist")
    require(info.get("CFBundleIdentifier") == BUNDLE_ID, "Unexpected iOS bundle identifier")
    require(info.get("CFBundleShortVersionString") == short_version, "Bundle version differs from pubspec")
    require(info.get("CFBundleVersion") == build_number, "Bundle build number differs from pubspec")
    require(info.get("CFBundlePackageType") == "APPL", "Runner is not an application bundle")
    require(info.get("CFBundleSupportedPlatforms") == ["iPhoneOS"], "Runner is not an iPhoneOS device bundle")
    minimum = os_version(info.get("MinimumOSVersion"))
    require(minimum == MINIMUM_OS, "Runner minimum iOS version must be 14.0")
    executable = info.get("CFBundleExecutable")
    require(isinstance(executable, str) and re.fullmatch(r"[A-Za-z0-9_.-]+", executable),
            "Invalid main executable name")
    require(bundle.mode(executable) & 0o111, "Runner executable permission was lost")
    main_slices = device_macho(bundle.read(executable), executable, 2, minimum, unsigned_main=True)
    main_signature = "linker/ad-hoc only (no CMS or Apple team)" if any(item["signatures"] for item in main_slices) else "none"
    require(not bundle.has("embedded.mobileprovision")
            and not any(name == "_CodeSignature" or name.startswith("_CodeSignature/") for name in bundle.paths),
            "Runner has signing material; expected an unsigned application")
    for framework in ("Flutter", "App"):
        root = f"Frameworks/{framework}.framework"
        framework_info = read_plist(bundle, f"{root}/Info.plist")
        require(framework_info.get("CFBundleExecutable") == framework, f"Invalid {framework} framework executable")
    binary_count = 1
    checked_binaries = {executable}
    for name in bundle.paths:
        if name.startswith("Frameworks/") and name.endswith(".framework/Info.plist"):
            root = name[:-len("/Info.plist")]
            framework_info = read_plist(bundle, name)
            framework_executable = framework_info.get("CFBundleExecutable")
            require(isinstance(framework_executable, str) and re.fullmatch(r"[A-Za-z0-9_.-]+", framework_executable),
                    f"Invalid framework executable: {name}")
            binary = f"{root}/{framework_executable}"
            require(bundle.mode(binary) & 0o111, f"Framework executable permission was lost: {binary}")
            device_macho(bundle.read(binary), binary, 6, minimum)
            checked_binaries.add(binary)
            binary_count += 1
        elif name.startswith("Frameworks/") and name.endswith(".dylib"):
            require(bundle.mode(name) & 0o111, f"Dylib executable permission was lost: {name}")
            device_macho(bundle.read(name), name, 6, minimum)
            checked_binaries.add(name)
            binary_count += 1
    # Frameworks may contain nested/versioned executables without a root Info.plist.
    # Do not silently accept another Mach-O platform merely because its filename is unfamiliar.
    for name in bundle.paths:
        if not name.startswith("Frameworks/") or name in checked_binaries or not stat.S_ISREG(bundle.mode(name)):
            continue
        data = bundle.read(name)
        if data[:4] in MACHO_MAGICS or data[:4] in FAT_MAGICS:
            require(bundle.mode(name) & 0o111, f"Embedded Mach-O permission was lost: {name}")
            device_macho(data, name, 6, minimum)
            binary_count += 1
    assets = "Frameworks/App.framework/flutter_assets/"
    require(any(name.startswith(assets) and stat.S_ISREG(bundle.mode(name)) for name in bundle.paths),
            "Missing Flutter assets")
    require(bundle.has(assets + "AssetManifest.bin"), "Missing Flutter AssetManifest.bin")
    require(not any(name.startswith(assets) and PurePosixPath(name).name in
                    ("kernel_blob.bin", "vm_snapshot_data", "isolate_snapshot_data") for name in bundle.paths),
            "Debug/JIT Flutter assets found; expected a Release AOT package")
    require(bundle.read("Assets.car"), "Missing compiled icon assets")
    for key in ("CFBundleIcons", "CFBundleIcons~ipad"):
        icons = info.get(key)
        require(isinstance(icons, dict), f"Missing primary icon declaration: {key}")
        primary = icons.get("CFBundlePrimaryIcon")
        require(isinstance(primary, dict) and primary.get("CFBundleIconName") == "AppIcon",
                f"Missing primary icon declaration: {key}")
        alternatives = icons.get("CFBundleAlternateIcons")
        require(isinstance(alternatives, dict), f"Missing alternate icon declaration: {key}")
        alternate = alternatives.get("AppIcon-1")
        require(isinstance(alternate, dict) and alternate.get("CFBundleIconName") == "AppIcon-1",
                f"Missing alternate icon declaration: {key}")
        for icon in (primary, alternate):
            files = icon.get("CFBundleIconFiles")
            require(isinstance(files, list) and files and all(isinstance(item, str) and item for item in files),
                    f"Missing compiled icon file names: {key}")
            for icon_file in files:
                basename = PurePosixPath(icon_file).name.removesuffix(".png")
                require(icon_file == PurePosixPath(icon_file).name and
                        any((name == basename + ".png" or name.startswith(basename + "@"))
                            and name.endswith(".png") and stat.S_ISREG(bundle.mode(name)) and bundle.read(name)
                            for name in bundle.paths), f"Missing compiled icon file: {icon_file}")
    for name, key in (("Main", "UIMainStoryboardFile"), ("LaunchScreen", "UILaunchStoryboardName")):
        require(info.get(key) == name, f"Missing {name} storyboard declaration")
        require(any((path == f"{name}.storyboardc" or path.endswith(f"/{name}.storyboardc"))
                    and stat.S_ISDIR(bundle.mode(path)) for path in bundle.paths), f"Missing compiled {name} storyboard")
    require(isinstance(info.get("UIApplicationSceneManifest"), dict), "Missing UIScene manifest")
    privacy = read_plist(bundle, "PrivacyInfo.xcprivacy")
    require(privacy.get("NSPrivacyTracking", False) is False and isinstance(privacy.get("NSPrivacyAccessedAPITypes"), list),
            "Invalid application privacy manifest")
    return {"version": version, "bundle_id": BUNDLE_ID, "minimum_ios": "14.0",
            "architecture": "device arm64", "signing": "unsigned", "main_signature": main_signature,
            "macho_binaries": binary_count}


def inspect_ipa(path, version, expected_inventory=None):
    try:
        with zipfile.ZipFile(path) as archive:
            bad_entry = archive.testzip()
            require(bad_entry is None, f"Corrupt IPA entry: {bad_entry}")
            bundle = ZipBundle(archive)
            report = validate_bundle(bundle, version)
            if expected_inventory is not None:
                require(bundle.inventory() == expected_inventory,
                        "IPA contents, symlinks or Unix permissions differ from the archive")
            return report
    except (zipfile.BadZipFile, UnicodeDecodeError, KeyError) as error:
        raise ValueError(f"Invalid IPA: {path}") from error


def sha256_file(path):
    digest = hashlib.sha256()
    with Path(path).open("rb") as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def validate_release(directory, expected_version=None):
    directory = Path(directory)
    ipas = list(directory.glob("*.ipa"))
    require(len(ipas) == 1, f"Expected exactly one IPA, found {len(ipas)}")
    ipa = ipas[0]
    require(ipa.is_file() and not ipa.is_symlink(), "IPA must be a regular file")
    match = IPA_PATTERN.fullmatch(ipa.name)
    require(match is not None, f"Unexpected unsigned IPA filename: {ipa.name}")
    version = match.group("version")
    require(expected_version is None or expected_version == version, "IPA filename differs from pubspec version")
    checksums = list(directory.glob("*.sha256"))
    require(len(checksums) == 1 and checksums[0].name == ipa.name + ".sha256", "Expected exactly one matching SHA-256 file")
    checksum = checksums[0]
    require(checksum.is_file() and not checksum.is_symlink() and checksum.stat().st_size <= 4096,
            "SHA-256 must be a small regular file")
    text = checksum.read_text(encoding="utf-8")
    checksum_match = re.fullmatch(r"([0-9a-f]{64})  ([^\r\n]+)\n?", text)
    require(checksum_match is not None and checksum_match.group(2) == ipa.name, "Invalid SHA-256 file or filename")
    digest = sha256_file(ipa)
    require(checksum_match.group(1) == digest, "IPA SHA-256 mismatch")
    report = inspect_ipa(ipa, version)
    report.update({"ipa": ipa.name, "sha256": digest})
    return report


def package_archive(archive, pubspec, output_directory):
    require(sys.platform == "darwin", "Packaging requires macOS ditto; IPA inspection is cross-platform")
    version = pubspec_version(pubspec)
    app = Path(archive) / "Products/Applications/Runner.app"
    bundle = DirectoryBundle(app)
    validate_bundle(bundle, version)
    inventory = bundle.inventory()
    output = Path(output_directory).resolve()
    output.mkdir(parents=True, exist_ok=True)
    filename = f"kira-{version}-ios-unsigned.ipa"
    with tempfile.TemporaryDirectory(prefix="kira-ios-package-") as temporary:
        staging = Path(temporary)
        payload = staging / "Payload"
        payload.mkdir()
        # ditto preserves executable modes, symbolic links and macOS metadata. No codesign/export.
        subprocess.run(["/usr/bin/ditto", str(app.resolve()), str(payload / "Runner.app")], check=True)
        require(DirectoryBundle(payload / "Runner.app").inventory() == inventory, "ditto changed the archive contents")
        ipa = staging / filename
        subprocess.run(["/usr/bin/ditto", "-c", "-k", "--sequesterRsrc", "--keepParent", str(payload), str(ipa)], check=True)
        inspect_ipa(ipa, version, inventory)
        extracted = staging / "unpacked"
        extracted.mkdir()
        subprocess.run(["/usr/bin/ditto", "-x", "-k", str(ipa), str(extracted)], check=True)
        unpacked = DirectoryBundle(extracted / "Payload/Runner.app")
        validate_bundle(unpacked, version)
        require(unpacked.inventory() == inventory, "Unpacked IPA differs from the archive")
        destination = output / filename
        # Same filesystem is not guaranteed for TMPDIR; copy only the sealed IPA, never a raw app.
        with ipa.open("rb") as source, destination.open("wb") as target:
            shutil.copyfileobj(source, target)
    digest = sha256_file(destination)
    (output / (filename + ".sha256")).write_text(f"{digest}  {filename}\n", encoding="utf-8")
    return validate_release(output, version)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    subparsers = parser.add_subparsers(dest="command", required=True)
    package = subparsers.add_parser("package")
    package.add_argument("--archive", default="build/ios/archive/Runner.xcarchive")
    package.add_argument("--pubspec", default="pubspec.yaml")
    package.add_argument("--output-dir", default="artifacts/ios-release")
    build_version = subparsers.add_parser("build-version")
    build_version.add_argument("--pubspec", default="pubspec.yaml")
    build_version.add_argument("--field", choices=("name", "number"), required=True)
    verify = subparsers.add_parser("verify-release")
    verify.add_argument("--artifact-dir", required=True)
    verify.add_argument("--pubspec")
    verify.add_argument("--print-version", action="store_true")
    args = parser.parse_args()
    try:
        if args.command == "build-version":
            name, number = version_parts(pubspec_version(args.pubspec))
            print(name if args.field == "name" else number)
            return 0
        if args.command == "package":
            report = package_archive(args.archive, args.pubspec, args.output_dir)
        else:
            expected = pubspec_version(args.pubspec) if args.pubspec else None
            report = validate_release(args.artifact_dir, expected)
        if getattr(args, "print_version", False):
            print(report["version"])
        else:
            import json
            print(json.dumps(report, ensure_ascii=False, indent=2))
    except (ValueError, OSError, subprocess.CalledProcessError) as error:
        print(f"iOS package validation failed: {error}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
