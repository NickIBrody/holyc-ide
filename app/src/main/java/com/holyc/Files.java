package com.holyc;

import android.content.Context;

import java.io.ByteArrayOutputStream;
import java.io.FileInputStream;
import java.io.FileOutputStream;

/** Tiny internal-storage read/write helpers (no dependencies). */
final class Files {
    private Files() {}

    static String read(Context ctx, String name) {
        try (FileInputStream in = ctx.openFileInput(name)) {
            ByteArrayOutputStream bos = new ByteArrayOutputStream();
            byte[] buf = new byte[4096];
            int r;
            while ((r = in.read(buf)) > 0) bos.write(buf, 0, r);
            return bos.toString("UTF-8");
        } catch (Exception e) {
            return "";
        }
    }

    static void write(Context ctx, String name, String content) {
        try (FileOutputStream out = ctx.openFileOutput(name, Context.MODE_PRIVATE)) {
            out.write(content.getBytes("UTF-8"));
        } catch (Exception ignored) {
        }
    }
}
