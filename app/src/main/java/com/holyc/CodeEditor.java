package com.holyc;

import android.content.Context;
import android.graphics.Canvas;
import android.graphics.Paint;
import android.graphics.Typeface;
import android.text.Layout;
import android.util.AttributeSet;
import android.widget.EditText;

/** EditText that draws a line-number gutter on the left, Pydroid-style. */
public class CodeEditor extends EditText {

    private final Paint gutterBg = new Paint();
    private final Paint numPaint = new Paint(Paint.ANTI_ALIAS_FLAG);
    private final Paint divider  = new Paint();
    private int gutterW;

    public CodeEditor(Context ctx, AttributeSet attrs) {
        super(ctx, attrs);
        init(ctx);
    }

    private void init(Context ctx) {
        float dp = ctx.getResources().getDisplayMetrics().density;

        gutterBg.setColor(0xFF1A1D24);

        numPaint.setTypeface(Typeface.MONOSPACE);
        numPaint.setTextSize(getTextSize() * 0.82f);
        numPaint.setColor(0xFF4B5263);
        numPaint.setTextAlign(Paint.Align.RIGHT);

        divider.setColor(0xFF2D3240);
        divider.setStrokeWidth(dp);

        // Wide enough for 4-digit line numbers + padding
        gutterW = (int) (numPaint.measureText("9999") + 20 * dp);
        setPadding(gutterW + (int)(6 * dp), getPaddingTop(), getPaddingRight(), getPaddingBottom());
    }

    @Override
    protected void onDraw(Canvas canvas) {
        Layout layout = getLayout();
        if (layout == null) { super.onDraw(canvas); return; }

        int sy = getScrollY();
        int h  = getHeight();

        // Fixed gutter background (covers visible height)
        canvas.drawRect(0, sy, gutterW, sy + h, gutterBg);
        canvas.drawLine(gutterW, sy, gutterW, sy + h, divider);

        // Line numbers — only for visible lines
        int first = layout.getLineForVertical(sy);
        int last  = layout.getLineForVertical(sy + h);
        float rx  = gutterW - (int)(6 * getResources().getDisplayMetrics().density);

        for (int i = first; i <= last && i < layout.getLineCount(); i++) {
            float y = layout.getLineBaseline(i) + getPaddingTop();
            canvas.drawText(Integer.toString(i + 1), rx, y, numPaint);
        }

        super.onDraw(canvas);
    }
}
