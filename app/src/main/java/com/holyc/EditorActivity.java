package com.holyc;

import android.app.Activity;
import android.content.Intent;
import android.database.Cursor;
import android.net.Uri;
import android.os.Bundle;
import android.provider.OpenableColumns;
import android.widget.EditText;
import android.widget.TextView;
import android.widget.Toast;

import java.io.ByteArrayOutputStream;
import java.io.File;
import java.io.InputStream;

public class EditorActivity extends Activity {

    private String fileName;
    private EditText code;

    @Override
    protected void onCreate(Bundle b) {
        super.onCreate(b);
        setContentView(R.layout.activity_editor);

        code = findViewById(R.id.code);

        if (Intent.ACTION_VIEW.equals(getIntent().getAction())) {
            loadFromUri(getIntent().getData());
        } else {
            fileName = getIntent().getStringExtra("file");
            if (fileName == null) fileName = "untitled.HC";
            code.setText(Files.read(this, fileName));
        }

        ((TextView) findViewById(R.id.title)).setText(fileName);
        findViewById(R.id.btn_back).setOnClickListener(v -> finish());
        findViewById(R.id.btn_run).setOnClickListener(v -> run());
    }

    /** Read file from external URI, copy to internal storage, show in editor. */
    private void loadFromUri(Uri uri) {
        if (uri == null) { fileName = "untitled.HC"; return; }

        fileName = "imported.HC";
        if ("file".equals(uri.getScheme())) {
            String path = uri.getPath();
            if (path != null) fileName = new File(path).getName();
        } else {
            try (Cursor c = getContentResolver().query(uri, null, null, null, null)) {
                if (c != null && c.moveToFirst()) {
                    int col = c.getColumnIndex(OpenableColumns.DISPLAY_NAME);
                    if (col >= 0) fileName = c.getString(col);
                }
            }
        }

        String content = "";
        try {
            InputStream is = getContentResolver().openInputStream(uri);
            if (is != null) {
                ByteArrayOutputStream buf = new ByteArrayOutputStream();
                byte[] tmp = new byte[4096];
                int n;
                while ((n = is.read(tmp)) != -1) buf.write(tmp, 0, n);
                is.close();
                content = buf.toString("UTF-8");
            }
        } catch (Exception e) {
            Toast.makeText(this, "Cannot read file: " + e.getMessage(), Toast.LENGTH_LONG).show();
        }

        Files.write(this, fileName, content);
        code.setText(content);
    }

    private void run() {
        save();
        String out;
        try {
            out = HolyCRuntime.compileAndRun(code.getText().toString());
        } catch (Throwable t) {
            out = "Native failure: " + t;
        }
        Intent i = new Intent(this, OutputActivity.class);
        i.putExtra("out", out);
        startActivity(i);
    }

    private void save() {
        Files.write(this, fileName, code.getText().toString());
    }

    @Override
    protected void onPause() {
        super.onPause();
        save();
    }
}
