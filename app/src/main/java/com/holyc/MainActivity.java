package com.holyc;

import android.app.Activity;
import android.app.AlertDialog;
import android.content.Context;
import android.content.Intent;
import android.content.SharedPreferences;
import android.os.Bundle;
import android.text.InputType;
import android.view.View;
import android.widget.Button;
import android.widget.EditText;
import android.widget.ListView;
import android.widget.TextView;

import java.io.File;
import java.util.ArrayList;
import java.util.Collections;

public class MainActivity extends Activity {

    private ListView list;
    private TextView empty;
    private final ArrayList<String> files = new ArrayList<>();
    private FileAdapter adapter;

    @Override
    protected void onCreate(Bundle b) {
        super.onCreate(b);
        setContentView(R.layout.activity_main);

        list  = findViewById(R.id.list);
        empty = findViewById(R.id.empty);
        Button btnNew = findViewById(R.id.btn_new);

        adapter = new FileAdapter(this, files);
        list.setAdapter(adapter);

        list.setOnItemClickListener((p, v, pos, id) -> openEditor(files.get(pos)));
        list.setOnItemLongClickListener((p, v, pos, id) -> { confirmDelete(files.get(pos)); return true; });
        btnNew.setOnClickListener(v -> promptNewFile());

        seedExamplesOnce();
    }

    @Override
    protected void onResume() {
        super.onResume();
        refresh();
    }

    private void refresh() {
        files.clear();
        String[] all = fileList();
        if (all != null)
            for (String f : all) if (f.endsWith(".HC")) files.add(f);
        Collections.sort(files);
        adapter.notifyDataSetChanged();
        empty.setVisibility(files.isEmpty() ? View.VISIBLE : View.GONE);
    }

    private void openEditor(String name) {
        Intent i = new Intent(this, EditorActivity.class);
        i.putExtra("file", name);
        startActivity(i);
    }

    private void promptNewFile() {
        final EditText in = new EditText(this);
        in.setInputType(InputType.TYPE_CLASS_TEXT);
        in.setHint("Name.HC");
        in.setTextColor(0xFFD0D4DE);
        new AlertDialog.Builder(this)
                .setTitle("New file")
                .setView(in)
                .setPositiveButton("Create", (d, w) -> {
                    String name = in.getText().toString().trim();
                    if (name.isEmpty()) return;
                    if (!name.endsWith(".HC")) name += ".HC";
                    File f = new File(getFilesDir(), name);
                    if (!f.exists())
                        Files.write(this, name, "U0 Main() {\n  \"Hello from HolyC!\\n\";\n}\n\nMain;\n");
                    openEditor(name);
                })
                .setNegativeButton("Cancel", null)
                .show();
    }

    private void confirmDelete(String name) {
        new AlertDialog.Builder(this)
                .setTitle(name)
                .setMessage("Delete this file?")
                .setPositiveButton("Delete", (d, w) -> { deleteFile(name); refresh(); })
                .setNegativeButton("Cancel", null)
                .show();
    }

    private void seedExamplesOnce() {
        SharedPreferences sp = getSharedPreferences("holyc", Context.MODE_PRIVATE);
        if (sp.getBoolean("seeded", false)) return;
        Files.write(this, "hello.HC", Examples.HELLO);
        Files.write(this, "factorial.HC", Examples.FACTORIAL);
        sp.edit().putBoolean("seeded", true).apply();
    }
}
