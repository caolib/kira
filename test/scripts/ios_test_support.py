"""Synthetic IPA fixtures; never run a build tool or access a real account."""

import hashlib
import importlib.util
import plistlib
import stat
import struct
import zipfile
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]


def load_script(filename, name):
    spec = importlib.util.spec_from_file_location(name, ROOT / "scripts" / filename)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def macho(platform=2, cpu=0x0100000C, filetype=2, minimum=0x000E0000, signed=False):
    commands = struct.pack("<6I", 0x32, 24, platform, minimum, 0x001A0000, 0)
    if signed:
        commands += struct.pack("<4I", 0x1D, 16, 0, 0)
    header = struct.pack("<8I", 0xFEEDFACF, cpu, 0, filetype, 2 if signed else 1, len(commands), 0, 0)
    return header + commands + b"synthetic executable data"


def signed_macho(adhoc=True, cms=False, malformed=False, version=0x20001, team=False):
    body = b"synthetic executable data"
    signature_offset = 32 + 24 + 16 + len(body)
    identifier = b"Runner\0"
    header_size = {0x20001: 44, 0x20400: 88}[version]
    team_identifier = b"APPLE-TEAM\0" if team else b""
    hash_offset = header_size + len(identifier) + len(team_identifier)
    directory_size = hash_offset + 32
    count = 2 if cms else 1
    directory_offset = 12 + count * 8
    signature_size = directory_offset + directory_size + (12 if cms else 0)
    commands = struct.pack("<6I", 0x32, 24, 2, 0x000E0000, 0x001A0000, 0)
    commands += struct.pack("<4I", 0x1D, 16, signature_offset, signature_size)
    image = struct.pack("<8I", 0xFEEDFACF, 0x0100000C, 0, 2, 2, len(commands), 0, 0) + commands + body
    directory = struct.pack(">9I4BI", 0xFADE0C02, directory_size, version, 2 if adhoc else 0,
                            hash_offset, header_size, 0, 1, signature_offset, 32, 2, 0, 12, 0)
    if version == 0x20400:
        directory += struct.pack(">IIIQQQQ", 0, header_size + len(identifier) if team else 0, 0, 0, 0, signature_offset, 1)
    directory += identifier + team_identifier + hashlib.sha256(image).digest()
    signature = struct.pack(">3I", 0xFADE0CC0, signature_size, count)
    signature += struct.pack(">2I", 0, directory_offset)
    if cms:
        signature += struct.pack(">2I", 0x10000, directory_offset + directory_size)
    signature += directory
    if cms:
        signature += struct.pack(">2I", 0xFADE0B01, 12) + b"CMS!"
    if malformed:
        signature = b"BAD!" + signature[4:]
    return image + signature


def fat_macho(slices):
    offset = 8 + len(slices) * 20
    table, data = [], []
    for content in slices:
        cpu, subtype = struct.unpack_from("<II", content, 4)
        table.append(struct.pack(">5I", cpu, subtype, offset, len(content), 0))
        data.append(content)
        offset += len(content)
    return struct.pack(">II", 0xCAFEBABE, len(slices)) + b"".join(table) + b"".join(data)


def fixture_entries(version="1.7.7+656"):
    short, build = version.split("+")
    short = short.split("-")[0]
    icons = {"CFBundlePrimaryIcon": {"CFBundleIconName": "AppIcon", "CFBundleIconFiles": ["AppIcon60x60"]},
             "CFBundleAlternateIcons": {"AppIcon-1": {"CFBundleIconName": "AppIcon-1",
                                                     "CFBundleIconFiles": ["AppIcon-160x60"]}}}
    info = {"CFBundleIdentifier": "io.github.caolib.kira", "CFBundleShortVersionString": short,
            "CFBundleVersion": build, "CFBundlePackageType": "APPL", "CFBundleExecutable": "Runner",
            "CFBundleSupportedPlatforms": ["iPhoneOS"], "MinimumOSVersion": "14.0",
            "CFBundleIcons": icons, "CFBundleIcons~ipad": icons,
            "UIMainStoryboardFile": "Main", "UILaunchStoryboardName": "LaunchScreen",
            "UIApplicationSceneManifest": {"UISceneConfigurations": {}}}
    regular = stat.S_IFREG | 0o644
    executable = stat.S_IFREG | 0o755
    directory = stat.S_IFDIR | 0o755
    entries = {"Info.plist": (regular, plistlib.dumps(info)), "Runner": (executable, macho()),
               "Assets.car": (regular, b"compiled asset catalog"),
               "AppIcon60x60@2x.png": (regular, b"primary png"),
               "AppIcon-160x60@2x.png": (regular, b"alternate png"),
               "PrivacyInfo.xcprivacy": (regular, plistlib.dumps({"NSPrivacyTracking": False,
                                                                "NSPrivacyAccessedAPITypes": []})),
               "Base.lproj/Main.storyboardc": (directory, b""),
               "Base.lproj/Main.storyboardc/UIViewController.nib": (regular, b"main nib"),
               "Base.lproj/LaunchScreen.storyboardc": (directory, b""),
               "Base.lproj/LaunchScreen.storyboardc/UIViewController.nib": (regular, b"launch nib")}
    for framework in ("Flutter", "App", "ExamplePlugin"):
        base = f"Frameworks/{framework}.framework/"
        entries[base + "Info.plist"] = (regular, plistlib.dumps({"CFBundleExecutable": framework}))
        entries[base + framework] = (executable, macho(filetype=6))
    entries["Frameworks/App.framework/flutter_assets/AssetManifest.bin"] = (regular, b"manifest")
    entries["Frameworks/App.framework/flutter_assets/assets/ic_launcher.png"] = (regular, b"asset png")
    entries["Frameworks/ExamplePlugin.framework/Info.link"] = (stat.S_IFLNK | 0o777, b"Info.plist")
    return entries


def write_ipa(path, entries=None, version="1.7.7+656", extra_entries=()):
    entries = fixture_entries(version) if entries is None else entries
    path = Path(path)
    path.parent.mkdir(parents=True, exist_ok=True)
    with zipfile.ZipFile(path, "w", compression=zipfile.ZIP_DEFLATED) as archive:
        for name, (mode, content) in entries.items():
            suffix = "/" if stat.S_ISDIR(mode) else ""
            entry = zipfile.ZipInfo("Payload/Runner.app/" + name + suffix)
            entry.create_system = 3
            entry.external_attr = mode << 16
            if stat.S_ISDIR(mode):
                entry.external_attr |= 0x10
            archive.writestr(entry, content)
        for name, mode, content in extra_entries:
            entry = zipfile.ZipInfo(name)
            entry.create_system = 3
            entry.external_attr = mode << 16
            archive.writestr(entry, content)
    checksum(path)
    return path


def checksum(path):
    path = Path(path)
    digest = hashlib.sha256(path.read_bytes()).hexdigest()
    path.with_name(path.name + ".sha256").write_text(f"{digest}  {path.name}\n", encoding="utf-8")


def update_info(entries, **values):
    mode, content = entries["Info.plist"]
    info = plistlib.loads(content)
    info.update(values)
    entries["Info.plist"] = mode, plistlib.dumps(info)
