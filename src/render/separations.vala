namespace Singularity.Apps.Publish {

    public class SeparationPreview {
        public Publication pub;
        public Gee.HashSet<string> enabled = new Gee.HashSet<string> ();
        public double scale = 1;
        public int page = -1;
        public Gee.HashMap<string, Cairo.ImageSurface> plates = new Gee.HashMap<string, Cairo.ImageSurface> ();
        public Cairo.ImageSurface? composite = null;

        public SeparationPreview (Publication pub) {
            this.pub = pub;
            foreach (string p in PrepressExport.plates (pub)) enabled.add (p);
        }

        public Rgba ink_rgb (string plate) {
            switch (plate) {
                case Inks.CYAN: return Rgba (0, 0.68, 0.94, 1);
                case Inks.MAGENTA: return Rgba (0.93, 0, 0.55, 1);
                case Inks.YELLOW: return Rgba (1, 0.95, 0, 1);
                case Inks.BLACK: return Rgba (0.14, 0.12, 0.13, 1);
                default:
                    var sw = pub.swatch (plate);
                    if (sw != null) return pub.resolve_screen (ColorRef.swatch (plate));
                    return Rgba (0.5, 0.5, 0.5, 1);
            }
        }

        private Cairo.ImageSurface render_plate (string plate, int w, int h) {
            var pp = PrepressExport.plate_publication (pub, plate);
            var surf = new Cairo.ImageSurface (Cairo.Format.RGB24, w, h);
            var cr = new Cairo.Context (surf);
            cr.set_source_rgb (1, 1, 1);
            cr.paint ();
            cr.scale (scale, scale);
            var r = new Renderer (pp);
            r.opts.print = true;
            r.opts.placeholders = false;
            r.opts.overset_marks = false;
            r.draw_page (cr, page, true);
            surf.flush ();
            return surf;
        }

        public void render (int page_index, double px_per_pt) {
            page = page_index;
            scale = px_per_pt;
            int w = int.max (1, (int) Math.ceil (pub.page_w (page) * scale)), h = int.max (1, (int) Math.ceil (pub.page_h (page) * scale));
            plates.clear ();
            foreach (string p in PrepressExport.plates (pub)) plates[p] = render_plate (p, w, h);
            build_composite ();
        }

        public void build_composite () {
            if (plates.size == 0) return;
            Cairo.ImageSurface? any = null;
            foreach (var s in plates.values) any = s;
            int w = any.get_width (), h = any.get_height ();
            var out_s = new Cairo.ImageSurface (Cairo.Format.RGB24, w, h);
            out_s.flush ();
            unowned uint8[] d = out_s.get_data ();
            int ds = out_s.get_stride ();
            bool le = GLib.ByteOrder.HOST == GLib.ByteOrder.LITTLE_ENDIAN;
            int ri = le ? 2 : 1, gi = le ? 1 : 2, bi = le ? 0 : 3;
            var acc = new double[w * h * 3];
            for (int i = 0; i < w * h * 3; i++) acc[i] = 1;
            foreach (var e in plates.entries) {
                if (!enabled.contains (e.key)) continue;
                var ink = ink_rgb (e.key);
                var s = e.value;
                unowned uint8[] sd = s.get_data ();
                int ss = s.get_stride ();
                for (int y = 0; y < h; y++) for (int x = 0; x < w; x++) {
                    double v = 1 - sd[y * ss + x * 4 + ri] / 255.0;
                    if (v <= 0.001) continue;
                    int o = (y * w + x) * 3;
                    acc[o] *= 1 - v * (1 - ink.r);
                    acc[o + 1] *= 1 - v * (1 - ink.g);
                    acc[o + 2] *= 1 - v * (1 - ink.b);
                }
            }
            for (int y = 0; y < h; y++) for (int x = 0; x < w; x++) {
                int o = (y * w + x) * 3, di = y * ds + x * 4;
                d[di + ri] = (uint8) Math.round (acc[o] * 255);
                d[di + gi] = (uint8) Math.round (acc[o + 1] * 255);
                d[di + bi] = (uint8) Math.round (acc[o + 2] * 255);
            }
            out_s.mark_dirty ();
            composite = out_s;
        }

        public Gee.HashMap<string, double?> ink_at (double page_x, double page_y) {
            var map = new Gee.HashMap<string, double?> ();
            int x = (int) (page_x * scale), y = (int) (page_y * scale);
            bool le = GLib.ByteOrder.HOST == GLib.ByteOrder.LITTLE_ENDIAN;
            foreach (var e in plates.entries) {
                var s = e.value;
                if (x < 0 || y < 0 || x >= s.get_width () || y >= s.get_height ()) continue;
                unowned uint8[] sd = s.get_data ();
                map[e.key] = 100 * (1 - sd[y * s.get_stride () + x * 4 + (le ? 2 : 1)] / 255.0);
            }
            return map;
        }

        public double total_at (double page_x, double page_y) {
            double t = 0;
            foreach (var e in ink_at (page_x, page_y).entries) t += e.value;
            return t;
        }
    }
}
