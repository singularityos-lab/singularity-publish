using Gtk;

namespace Singularity.Apps.Publish {

    public class CanvasRulers : Object {
        public const int SIZE = 20;
        private weak PageCanvas canvas;

        public CanvasRulers (PageCanvas canvas) {
            this.canvas = canvas;
            canvas.add_css_class ("sx-rulers");
        }

        public bool on_ruler (double x, double y, int height) {
            return x < SIZE || y > height - SIZE;
        }

        private static bool is_major (double v, double major) {
            double m = Math.fmod (Math.fabs (v) + 1e-6, major);
            return m < 1e-4 || Math.fabs (m - major) < 1e-4;
        }

        public void draw (Cairo.Context cr, int w, int h) {
            var fg = canvas.get_color ();
            double top = h - SIZE;
            bool dark = fg.red * 0.3 + fg.green * 0.59 + fg.blue * 0.11 > 0.5;
            double bg = dark ? 0.17 : 0.95;
            cr.save ();
            cr.set_source_rgb (bg, bg, bg);
            cr.rectangle (0, 0, SIZE, top);
            cr.rectangle (0, top, w, SIZE);
            cr.fill ();
            cr.set_source_rgba (fg.red, fg.green, fg.blue, 0.12);
            cr.set_line_width (1);
            cr.move_to (SIZE, top + 0.5);
            cr.line_to (w, top + 0.5);
            cr.move_to (SIZE - 0.5, 0);
            cr.line_to (SIZE - 0.5, top);
            cr.stroke ();
            var sl = canvas.active_slot () ?? (canvas.slots.size > 0 ? canvas.slots[0] : null);
            if (sl == null) {
                cr.restore ();
                return;
            }
            double unit_px = Units.factor (canvas.units) * canvas.scale;
            double[] steps = { 1, 2, 5, 10, 20, 50, 100, 200, 500, 1000 };
            double major = 1;
            foreach (double st in steps) {
                major = st;
                if (st * unit_px >= 64) break;
            }
            double minor = major / (major >= 10 && ((int) major) % 10 == 0 ? 10 : 5);
            double ox, oy;
            canvas.to_widget (sl.x, sl.y, out ox, out oy);
            var layout = new Pango.Layout (canvas.get_pango_context ());
            var fd = new Pango.FontDescription ();
            fd.set_family ("Inter");
            fd.set_absolute_size (9 * Pango.SCALE);
            layout.set_font_description (fd);
            cr.set_line_width (1);
            double start = Math.floor ((SIZE - ox) / unit_px / minor) * minor;
            for (double v = start; ox + v * unit_px < w; v += minor) {
                double x = Math.round (ox + v * unit_px) + 0.5;
                if (x < SIZE) continue;
                bool maj = is_major (v, major);
                cr.set_source_rgba (fg.red, fg.green, fg.blue, maj ? 0.45 : 0.3);
                cr.move_to (x, top);
                cr.line_to (x, maj ? h - 3 : top + 4);
                cr.stroke ();
                if (!maj) continue;
                layout.set_text (XmlOut.num (Math.round (v)), -1);
                int lw, lh;
                layout.get_pixel_size (out lw, out lh);
                cr.set_source_rgba (fg.red, fg.green, fg.blue, 0.65);
                cr.move_to (x + 3, h - lh - 2);
                Pango.cairo_show_layout (cr, layout);
            }
            start = Math.floor ((0 - oy) / unit_px / minor) * minor;
            for (double v = start; oy + v * unit_px < top; v += minor) {
                double y = Math.round (oy + v * unit_px) + 0.5;
                if (y < 0) continue;
                bool maj = is_major (v, major);
                cr.set_source_rgba (fg.red, fg.green, fg.blue, maj ? 0.45 : 0.3);
                cr.move_to (SIZE, y);
                cr.line_to (maj ? 3 : SIZE - 4, y);
                cr.stroke ();
                if (!maj) continue;
                layout.set_text (XmlOut.num (Math.round (v)), -1);
                cr.set_source_rgba (fg.red, fg.green, fg.blue, 0.65);
                cr.save ();
                cr.translate (2, y + 3);
                cr.rotate (Math.PI / 2);
                cr.move_to (0, -13);
                Pango.cairo_show_layout (cr, layout);
                cr.restore ();
            }
            cr.set_source_rgba (fg.red, fg.green, fg.blue, 0.85);
            if (canvas.cur_px > SIZE) {
                cr.move_to (Math.round (canvas.cur_px) + 0.5, top);
                cr.line_to (Math.round (canvas.cur_px) + 0.5, h);
            }
            if (canvas.cur_py < top) {
                cr.move_to (0, Math.round (canvas.cur_py) + 0.5);
                cr.line_to (SIZE, Math.round (canvas.cur_py) + 0.5);
            }
            cr.stroke ();
            cr.restore ();
        }
    }
}
