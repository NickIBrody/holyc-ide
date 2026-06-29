package com.holyc;

import android.app.Activity;
import android.os.Bundle;
import android.widget.TextView;

/** Shows captured program output (or the compiler error). */
public class OutputActivity extends Activity {

    @Override
    protected void onCreate(Bundle b) {
        super.onCreate(b);
        setContentView(R.layout.activity_output);

        String out = getIntent().getStringExtra("out");
        if (out == null || out.isEmpty()) out = "(no output)";
        ((TextView) findViewById(R.id.out)).setText(out);

        findViewById(R.id.btn_back).setOnClickListener(v -> finish());
    }
}
