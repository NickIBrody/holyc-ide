package com.holyc;

import android.content.Context;
import android.view.LayoutInflater;
import android.view.View;
import android.view.ViewGroup;
import android.widget.ArrayAdapter;
import android.widget.TextView;
import java.io.File;
import java.util.List;

public class FileAdapter extends ArrayAdapter<String> {
    private final Context ctx;

    public FileAdapter(Context ctx, List<String> items) {
        super(ctx, R.layout.list_item, items);
        this.ctx = ctx;
    }

    @Override
    public View getView(int pos, View convertView, ViewGroup parent) {
        if (convertView == null)
            convertView = LayoutInflater.from(ctx).inflate(R.layout.list_item, parent, false);

        String name = getItem(pos);
        ((TextView) convertView.findViewById(R.id.filename)).setText(name);

        String info = "";
        try {
            File f = new File(ctx.getFilesDir(), name);
            long bytes = f.length();
            int lines = 0;
            if (bytes > 0) {
                byte[] data = new byte[(int) Math.min(bytes, 65536)];
                java.io.FileInputStream fis = new java.io.FileInputStream(f);
                int read = fis.read(data);
                fis.close();
                for (int k = 0; k < read; k++) if (data[k] == '\n') lines++;
                info = lines + (lines == 1 ? " line" : " lines") + "  ·  " + bytes + " B";
            }
        } catch (Exception ignored) {}
        ((TextView) convertView.findViewById(R.id.info)).setText(info);

        return convertView;
    }
}
