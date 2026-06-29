package com.holyc;

import android.app.Activity;
import android.content.Intent;
import android.os.Bundle;
import android.widget.Button;
import android.widget.EditText;
import android.widget.TextView;

/** Code editor with a Run button. Auto-saves on pause. */
public class EditorActivity extends Activity {

    private String fileName;
    private EditText code;

    @Override
    protected void onCreate(Bundle b) {
        super.onCreate(b);
        setContentView(R.layout.activity_editor);

        fileName = getIntent().getStringExtra("file");
        if (fileName == null) fileName = "untitled.HC";

        ((TextView) findViewById(R.id.title)).setText(fileName);
        code = findViewById(R.id.code);
        code.setText(Files.read(this, fileName));

        findViewById(R.id.btn_back).setOnClickListener(v -> finish());
        findViewById(R.id.btn_run).setOnClickListener(v -> run());
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
