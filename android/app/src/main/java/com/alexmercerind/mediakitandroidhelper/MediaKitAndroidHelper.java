/**
 * Minimal port of package:media_kit_libs_android_video's MediaKitAndroidHelper.
 *
 * Kira downloads libmpv / libmediakitandroidhelper on demand and does not ship
 * media_kit_libs_android_video (to keep the APK small). media_kit_video still
 * reflects into this class for Surface global refs, and media_kit's
 * AndroidHelper.ensureInitialized() busy-waits on MediaKitAndroidHelperGetJavaVM
 * until setApplicationContextNative stores the JavaVM — without this class the
 * UI freezes forever after System.load.
 *
 * Source reference:
 * media_kit_libs_android_video → com.alexmercerind.mediakitandroidhelper.MediaKitAndroidHelper
 */
package com.alexmercerind.mediakitandroidhelper;

import android.content.Context;
import android.net.Uri;

import androidx.annotation.Keep;

@Keep
public class MediaKitAndroidHelper {
    static {
        // Bundled installs load via System.loadLibrary. On-demand installs use
        // System.load(absolutePath) from MainActivity before touching this class.
        try {
            System.loadLibrary("mediakitandroidhelper");
        } catch (UnsatisfiedLinkError ignored) {
            // Expected when the .so lives under app files/ and was already
            // System.load'd by MainActivity.loadLibraries.
        }
    }

    private static Context applicationContext = null;

    public static native long newGlobalObjectRef(Object obj);

    public static native void deleteGlobalObjectRef(long ref);

    public static native String copyAssetToFilesDir(String assetName);

    private static native void setApplicationContextNative(Context context);

    public static void setApplicationContextJava(Context context) {
        applicationContext = context;
        setApplicationContextNative(context);
    }

    public static native int openFileDescriptorNative(String uri);

    public static int openFileDescriptorJava(String uri) {
        try {
            final Uri object = Uri.parse(uri);
            return applicationContext
                    .getContentResolver()
                    .openFileDescriptor(object, "r")
                    .detachFd();
        } catch (Throwable e) {
            e.printStackTrace();
            return -1;
        }
    }
}
