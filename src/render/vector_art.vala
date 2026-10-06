namespace Singularity.Apps.Publish {

    public class VectorArt {
        public Rsvg.Handle? svg = null;
        public Poppler.Document? pdf = null;
        public string kind = "";
        public int pages = 1;

        public static string? atelier_svg (uint8[] data) {
            if (data.length < 4 || data[0] != 'P' || data[1] != 'K') return null;
            try {
                var zip = new ZipReader (data);
                string? mt = zip.read_text ("mimetype");
                if (mt == null || !mt.has_prefix ("application/x-atelier")) return null;
                foreach (string n in new string[] { "sketch/sketch.svg", "pattern/pattern.svg" }) {
                    if (zip.has (n)) return zip.read_text (n);
                }
                foreach (string n in zip.names ()) if (n.has_prefix ("flats/") && n.has_suffix (".svg")) return zip.read_text (n);
            } catch (Error e) {
            }
            return null;
        }

        public static VectorArt? load (uint8[] data) {
            var v = new VectorArt ();
            try {
                if (data.length > 5 && data[0] == '%' && data[1] == 'P' && data[2] == 'D' && data[3] == 'F') {
                    v.pdf = new Poppler.Document.from_bytes (new Bytes (data), null);
                    v.kind = "pdf";
                    v.pages = v.pdf.get_n_pages ();
                    return v.pages > 0 ? v : null;
                }
                string? inner = atelier_svg (data);
                if (inner != null) {
                    v.svg = new Rsvg.Handle.from_data (inner.data);
                    v.kind = "atelier";
                    return v;
                }
                string head = Bin.head (data, 1024);
                if (head.contains ("<svg") || (head.has_prefix ("<?xml") && Bin.head (data, 4096).contains ("<svg"))) {
                    v.svg = new Rsvg.Handle.from_data (data);
                    v.kind = "svg";
                    return v;
                }
            } catch (Error e) {
            }
            return null;
        }

        public void size (int page, out double w, out double h) {
            w = 100;
            h = 100;
            if (pdf != null) {
                var pg = pdf.get_page (page.clamp (0, pages - 1));
                if (pg != null) pg.get_size (out w, out h);
                return;
            }
            if (svg != null) {
                double pw, ph;
                if (svg.get_intrinsic_size_in_pixels (out pw, out ph)) {
                    w = pw * 0.75;
                    h = ph * 0.75;
                }
            }
        }

        public void render (Cairo.Context cr, int page) {
            double w, h;
            size (page, out w, out h);
            if (pdf != null) {
                var pg = pdf.get_page (page.clamp (0, pages - 1));
                if (pg != null) pg.render_for_printing (cr);
                return;
            }
            if (svg != null) {
                try {
                    var vp = Rsvg.Rectangle () { x = 0, y = 0, width = w, height = h };
                    svg.render_document (cr, vp);
                } catch (Error e) {
                }
            }
        }

        public Cairo.ImageSurface raster (int page, double scale) {
            double w, h;
            size (page, out w, out h);
            var surf = new Cairo.ImageSurface (Cairo.Format.ARGB32, int.max (1, (int) Math.ceil (w * scale)), int.max (1, (int) Math.ceil (h * scale)));
            var cr = new Cairo.Context (surf);
            cr.scale (scale, scale);
            if (pdf != null) {
                cr.set_source_rgb (1, 1, 1);
                cr.paint ();
            }
            render (cr, page);
            surf.flush ();
            return surf;
        }
    }
}
