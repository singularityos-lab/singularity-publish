namespace Singularity.Apps.Publish {

    public enum InkKind {
        PROCESS,
        SPOT,
        ALL
    }

    public class InkColor {
        public InkKind kind = InkKind.PROCESS;
        public double c = 0;
        public double m = 0;
        public double y = 0;
        public double k = 0;
        public string spot = "";
        public double tint = 1;
        public bool overprint = false;

        public string key () {
            return "%d|%.4f|%.4f|%.4f|%.4f|%s|%.4f|%d".printf ((int) kind, c, m, y, k, spot, tint, overprint ? 1 : 0);
        }

        public void process_values (out double oc, out double om, out double oy, out double ok) {
            if (kind == InkKind.ALL) {
                oc = om = oy = ok = tint;
                return;
            }
            double t = kind == InkKind.SPOT ? tint : 1;
            oc = c * t;
            om = m * t;
            oy = y * t;
            ok = k * t;
        }

        public double ink_for (string plate) {
            if (kind == InkKind.ALL) return tint;
            if (kind == InkKind.SPOT) return plate == spot ? tint : 0;
            switch (plate) {
                case Inks.CYAN: return c;
                case Inks.MAGENTA: return m;
                case Inks.YELLOW: return y;
                case Inks.BLACK: return k;
                default: return 0;
            }
        }
    }

    public class Inks {
        public const string CYAN = "Cyan";
        public const string MAGENTA = "Magenta";
        public const string YELLOW = "Yellow";
        public const string BLACK = "Black";
        public const string REGISTRATION = "Registration";

        public static string[] process () {
            return { CYAN, MAGENTA, YELLOW, BLACK };
        }

        public static InkColor? resolve (Publication pub, ColorManager cm, string raw) {
            if (raw == ColorRef.NONE) return null;
            string spec = pub.canonical (raw);
            var ink = new InkColor ();
            if (ColorRef.is_swatch (spec)) {
                string name = ColorRef.swatch_name (spec);
                double t = (ColorRef.tint_of (spec) / 100).clamp (0, 1);
                var sw = pub.swatch (name);
                if (sw == null) {
                    ink.k = t;
                    return ink;
                }
                if (name == REGISTRATION) {
                    ink.kind = InkKind.ALL;
                    ink.tint = t;
                    return ink;
                }
                double c, m, y, k;
                if (sw.model == ColorModel.CMYK) {
                    c = sw.c;
                    m = sw.m;
                    y = sw.y;
                    k = sw.k;
                } else {
                    cm.rgb_to_cmyk (sw.r, sw.g, sw.b, out c, out m, out y, out k);
                }
                if (sw.spot) {
                    ink.kind = InkKind.SPOT;
                    ink.spot = sw.name;
                    ink.tint = t;
                    ink.c = c;
                    ink.m = m;
                    ink.y = y;
                    ink.k = k;
                    return ink;
                }
                if (sw.model == ColorModel.RGB && t < 0.9999) {
                    var v = ColorMath.tint (Rgba (sw.r, sw.g, sw.b, 1), t * 100);
                    cm.rgb_to_cmyk (v.r, v.g, v.b, out c, out m, out y, out k);
                    t = 1;
                }
                ink.c = c * t;
                ink.m = m * t;
                ink.y = y * t;
                ink.k = k * t;
                return ink;
            }
            if (spec.has_prefix ("cmyk:")) {
                string[] f = spec.substring (5).split (",");
                if (f.length == 4) {
                    ink.c = Units.parse_num (f[0], 0).clamp (0, 1);
                    ink.m = Units.parse_num (f[1], 0).clamp (0, 1);
                    ink.y = Units.parse_num (f[2], 0).clamp (0, 1);
                    ink.k = Units.parse_num (f[3], 0).clamp (0, 1);
                    return ink;
                }
            }
            Rgba c;
            if (!Rgba.parse_hex (spec, out c)) c = Rgba (0, 0, 0, 1);
            cm.rgb_to_cmyk (c.r, c.g, c.b, out ink.c, out ink.m, out ink.y, out ink.k);
            return ink;
        }

        public static bool is_rich_black_free (InkColor ink) {
            return ink.kind == InkKind.PROCESS && ink.c < 0.0001 && ink.m < 0.0001 && ink.y < 0.0001 && ink.k > 0.9999;
        }
    }

    public class SentinelOutput : ColorOutput {
        public const int MARK_KNOCKOUT = 251;
        public const int MARK_OVERPRINT = 253;
        public ColorManager cm;
        public Gee.ArrayList<InkColor> palette = new Gee.ArrayList<InkColor> ();
        private Gee.HashMap<string, int> index = new Gee.HashMap<string, int> ();
        private bool overprint_black;

        public SentinelOutput (Publication pub, ColorManager? manager = null) {
            cm = manager ?? ColorManager.for_settings (pub.settings);
            overprint_black = pub.settings.overprint_black;
        }

        public int add (InkColor ink) {
            string key = ink.key ();
            if (index.has_key (key)) return index[key];
            int i = palette.size;
            palette.add (ink);
            index[key] = i;
            return i;
        }

        public override Rgba map (Publication pub, string spec, Rgba screen) {
            if (spec == ColorRef.NONE) return screen;
            var ink = Inks.resolve (pub, cm, spec);
            if (ink == null) return screen;
            ink.overprint = overprint || (overprint_black && Inks.is_rich_black_free (ink));
            return encode (add (ink), ink.overprint, screen.a);
        }

        public override Rgba map_raw (Rgba c) {
            var ink = new InkColor ();
            cm.rgb_to_cmyk (c.r, c.g, c.b, out ink.c, out ink.m, out ink.y, out ink.k);
            return encode (add (ink), false, c.a);
        }

        public static Rgba encode (int i, bool overprint, double alpha) {
            return Rgba (((i >> 8) & 0xff) / 255.0, (i & 0xff) / 255.0, (overprint ? MARK_OVERPRINT : MARK_KNOCKOUT) / 255.0, alpha);
        }

        public InkColor? decode (double r, double g, double b, out bool overprint_flag) {
            overprint_flag = false;
            int rb = (int) Math.round (r * 255), gb = (int) Math.round (g * 255), bb = (int) Math.round (b * 255);
            if (Math.fabs (r * 255 - rb) > 0.02 || Math.fabs (g * 255 - gb) > 0.02 || Math.fabs (b * 255 - bb) > 0.02) return null;
            if (bb != MARK_KNOCKOUT && bb != MARK_OVERPRINT) return null;
            int i = (rb << 8) | gb;
            if (i < 0 || i >= palette.size) return null;
            overprint_flag = bb == MARK_OVERPRINT;
            return palette[i];
        }
    }

    public class PlateOutput : ColorOutput {
        public string plate;
        public ColorManager cm;
        private bool overprint_black;
        private Gee.HashMap<Cairo.ImageSurface, Cairo.ImageSurface> images = new Gee.HashMap<Cairo.ImageSurface, Cairo.ImageSurface> ();

        public PlateOutput (Publication pub, string plate) {
            this.plate = plate;
            cm = ColorManager.for_settings (pub.settings);
            overprint_black = pub.settings.overprint_black;
        }

        public override Rgba map (Publication pub, string spec, Rgba screen) {
            if (spec == ColorRef.NONE) return screen;
            var ink = Inks.resolve (pub, cm, spec);
            if (ink == null) return screen;
            double v = ink.ink_for (plate).clamp (0, 1);
            bool op = overprint || (overprint_black && Inks.is_rich_black_free (ink));
            if (op && v < 0.0001) return Rgba (1, 1, 1, 0);
            return Rgba (1 - v, 1 - v, 1 - v, screen.a);
        }

        public override Rgba map_raw (Rgba c) {
            double cc, m, y, k;
            cm.rgb_to_cmyk (c.r, c.g, c.b, out cc, out m, out y, out k);
            double v = 0;
            switch (plate) {
                case Inks.CYAN: v = cc; break;
                case Inks.MAGENTA: v = m; break;
                case Inks.YELLOW: v = y; break;
                case Inks.BLACK: v = k; break;
            }
            return Rgba (1 - v, 1 - v, 1 - v, c.a);
        }

        public override Cairo.ImageSurface? map_image (Cairo.ImageSurface src) {
            if (images.has_key (src)) return images[src];
            int channel = -1;
            switch (plate) {
                case Inks.CYAN: channel = 0; break;
                case Inks.MAGENTA: channel = 1; break;
                case Inks.YELLOW: channel = 2; break;
                case Inks.BLACK: channel = 3; break;
            }
            src.flush ();
            int w = src.get_width (), h = src.get_height ();
            var cmyk = channel >= 0 ? cm.surface_to_cmyk (src) : new uint8[0];
            var dst = new Cairo.ImageSurface (Cairo.Format.ARGB32, w, h);
            unowned uint8[] s = src.get_data ();
            unowned uint8[] d = dst.get_data ();
            int ss = src.get_stride (), ds = dst.get_stride ();
            bool le = GLib.ByteOrder.HOST == GLib.ByteOrder.LITTLE_ENDIAN;
            bool alpha = src.get_format () == Cairo.Format.ARGB32;
            for (int y = 0; y < h; y++) {
                for (int x = 0; x < w; x++) {
                    uint a = alpha ? s[y * ss + x * 4 + (le ? 3 : 0)] : 255;
                    uint ink = channel >= 0 ? cmyk[(y * w + x) * 4 + channel] : 0;
                    uint g = (255 - ink) * a / 255;
                    int di = y * ds + x * 4;
                    d[di] = (uint8) g;
                    d[di + 1] = (uint8) g;
                    d[di + 2] = (uint8) g;
                    d[di + 3] = (uint8) a;
                    if (!le) {
                        d[di] = (uint8) a;
                        d[di + 3] = (uint8) g;
                    }
                }
            }
            dst.mark_dirty ();
            images[src] = dst;
            return dst;
        }
    }

    public class SheetBoxes {
        public Rect trim;
        public Rect bleed;
        public double height;

        public SheetBoxes (Rect trim, Rect bleed, double height) {
            this.trim = trim;
            this.bleed = bleed;
            this.height = height;
        }
    }

    public class PrepressExport {
        public static Gee.ArrayList<string> plates (Publication pub) {
            var list = new Gee.ArrayList<string> ();
            foreach (string p in Inks.process ()) list.add (p);
            foreach (var sw in pub.swatches) {
                if (!sw.spot || sw.name == Inks.REGISTRATION) continue;
                if (pub.swatch_in_use (sw.name) || spot_in_text (pub, sw.name)) list.add (sw.name);
            }
            return list;
        }

        private static bool spot_in_text (Publication pub, string name) {
            foreach (var st in pub.styles.character) if (st.chars.color != null && ColorRef.swatch_name (st.chars.color) == name) return true;
            bool found = false;
            pub.walk ((r) => {
                var tb = r.item as TableItem;
                if (tb != null) foreach (var row in tb.cells) foreach (var c in row) foreach (var p in c.story.paras) foreach (var run in p.runs) {
                    if (run.fmt.color != null && ColorRef.swatch_name (run.fmt.color) == name) found = true;
                }
                return !found;
            });
            return found;
        }

        public static Publication plate_publication (Publication pub, string plate) {
            var p = pub.clone ();
            p.output = new PlateOutput (p, plate);
            return p;
        }

        public static Gee.ArrayList<SheetBoxes> boxes (Exporter ex, Gee.ArrayList<Sheet> sheets) {
            var pub = ex.pub;
            var list = new Gee.ArrayList<SheetBoxes> ();
            foreach (var sh in sheets) {
                var media = Rect (0, 0, sh.w, sh.h);
                var trim = media;
                var bleed = media;
                bool any = false;
                foreach (var s in sh.slots) {
                    var t = Rect (s.x, s.y, s.w, s.h);
                    var br = ex.opts.bleed ? pub.bleed_rect (s.page) : pub.page_rect (s.page);
                    var b = Rect (s.x + br.x * s.scale, s.y + br.y * s.scale, br.w * s.scale, br.h * s.scale);
                    trim = any ? trim.union (t) : t;
                    bleed = any ? bleed.union (b) : b;
                    any = true;
                }
                bleed = clip (bleed.union (trim), media);
                trim = clip (trim, bleed);
                list.add (new SheetBoxes (trim, bleed, sh.h));
            }
            return list;
        }

        private static Rect clip (Rect r, Rect to) {
            double x0 = double.max (r.x, to.x), y0 = double.max (r.y, to.y);
            double x1 = double.min (r.x2 (), to.x2 ()), y1 = double.min (r.y2 (), to.y2 ());
            return Rect (x0, y0, double.max (0, x1 - x0), double.max (0, y1 - y0));
        }

        private static string temp_path () {
            return Path.build_filename (Environment.get_tmp_dir (), "publish-prepress-%u-%lld.pdf".printf (Random.next_int (), get_monotonic_time ()));
        }

        private static void set_metadata (Cairo.PdfSurface surf, Publication pub) {
            if (pub.meta.title != "") surf.set_metadata (Cairo.PdfMetadata.TITLE, pub.meta.title);
            if (pub.meta.author != "") surf.set_metadata (Cairo.PdfMetadata.AUTHOR, pub.meta.author);
            if (pub.meta.subject != "") surf.set_metadata (Cairo.PdfMetadata.SUBJECT, pub.meta.subject);
            if (pub.meta.keywords != "") surf.set_metadata (Cairo.PdfMetadata.KEYWORDS, pub.meta.keywords);
            surf.set_metadata (Cairo.PdfMetadata.CREATOR, "Singularity Publish");
        }

        public static int export_pdf (Publication pub, ExportOptions opts, string path) throws Error {
            if (opts.separations) return export_separations (pub, opts, path);
            var copy = pub.clone ();
            var cm = ColorManager.for_settings (copy.settings);
            var sentinel = new SentinelOutput (copy, cm);
            copy.output = sentinel;
            var ex = new Exporter (copy, opts);
            var sheets = ex.sheets ();
            if (sheets.size == 0) throw new FormatError.INVALID (_("There are no pages to export."));
            string tmp = temp_path ();
            try {
                var surf = new Cairo.PdfSurface (tmp, sheets[0].w, sheets[0].h);
                surf.restrict_to_version (Cairo.PdfVersion.VERSION_1_4);
                set_metadata (surf, pub);
                ex.prepare_links (sheets);
                var cr = new Cairo.Context (surf);
                bool flatten = opts.color_mode == ColorMode.PDFX1A || opts.color_mode == ColorMode.PDFX3;
                foreach (var sh in sheets) {
                    surf.set_size (sh.w, sh.h);
                    if (opts.impose == ImposeMode.NONE && sh.slots.size == 1) surf.set_page_label (pub.page_label (sh.slots[0].page));
                    var regions = new Gee.HashMap<int, Rect?> ();
                    if (flatten) {
                        var skip = new Gee.HashSet<int> ();
                        foreach (var slot in sh.slots) {
                            Rect? area = transparent_area (pub, slot.page, skip);
                            if (area != null) regions[slot.page] = area;
                        }
                        ex.renderer.opts.skip = skip.size > 0 ? skip : null;
                    }
                    ex.draw_sheet (cr, sh);
                    if (regions.size > 0) {
                        foreach (var slot in sh.slots) if (regions.has_key (slot.page)) paint_flattened (cr, pub, slot, regions[slot.page]);
                        ex.renderer.opts.skip = null;
                    }
                    ex.emit_destinations (cr, sh);
                    cr.show_page ();
                }
                ex.add_outline (surf);
                surf.finish ();
                if (surf.status () != Cairo.Status.SUCCESS) throw new FileError.FAILED (_("Could not write the PDF: %s").printf (surf.status ().to_string ()));
                uint8[] data;
                FileUtils.get_data (tmp, out data);
                var pp = new PdfPrepress (sentinel, cm);
                pp.standard = opts.color_mode;
                pp.title = pub.meta.title;
                pp.boxes = boxes (ex, sheets);
                FileUtils.set_data (path, pp.process (data));
            } finally {
                FileUtils.unlink (tmp);
            }
            return sheets.size;
        }

        public static bool is_transparent (Publication pub, Item it) {
            if (it.opacity < 0.999 || it.shadow.enabled || it.effects.any ()) return true;
            foreach (var st in it.fill.stops) if (st.opacity < 0.999) return true;
            var im = it as ImageFrame;
            if (im != null) {
                var inf = ImageStore.get_default ().info (pub, im);
                if (inf != null && inf.has_alpha) return true;
            }
            var g = it as GroupItem;
            if (g != null) foreach (var c in g.children) if (is_transparent (pub, c)) return true;
            return false;
        }

        public static Rect? transparent_area (Publication pub, int page, Gee.HashSet<int> skip) {
            if (page < 0 || page >= pub.pages.size) return null;
            var items = new Gee.ArrayList<Item> ();
            items.add_all (pub.master_items_for (page));
            items.add_all (pub.pages[page].items);
            Rect? area = null;
            foreach (var it in items) {
                if (it.hidden || !is_transparent (pub, it)) continue;
                skip.add (it.id);
                double grow = 2;
                if (it.shadow.enabled) grow += Math.fabs (it.shadow.dx) + Math.fabs (it.shadow.dy) + it.shadow.blur * 2;
                if (it.effects.glow) grow += it.effects.glow_size * 2;
                if (it.effects.reflection) grow += it.bounds ().h * it.effects.reflection_size + it.effects.reflection_distance;
                var b = it.bounds ();
                var r = Rect (b.x - grow, b.y - grow, b.w + 2 * grow, b.h + 2 * grow);
                area = area == null ? r : ((Rect) area).union (r);
            }
            if (area == null) return null;
            var bl = pub.bleed_rect (page);
            double x0 = double.max (area.x, bl.x), y0 = double.max (area.y, bl.y);
            double x1 = double.min (area.x2 (), bl.x2 ()), y1 = double.min (area.y2 (), bl.y2 ());
            if (x1 <= x0 || y1 <= y0) return null;
            return Rect (x0, y0, x1 - x0, y1 - y0);
        }

        public const double FLATTEN_PPI = 300;

        private static void paint_flattened (Cairo.Context cr, Publication pub, SheetSlot slot, Rect area) {
            double sc = FLATTEN_PPI / 72.0;
            int w = int.max (1, (int) Math.ceil (area.w * sc)), h = int.max (1, (int) Math.ceil (area.h * sc));
            var img = new Cairo.ImageSurface (Cairo.Format.RGB24, w, h);
            var ic = new Cairo.Context (img);
            ic.set_source_rgb (1, 1, 1);
            ic.paint ();
            ic.scale (sc, sc);
            ic.translate (-area.x, -area.y);
            var r = new Renderer (pub);
            r.opts.print = true;
            r.opts.placeholders = false;
            r.opts.overset_marks = false;
            r.draw_page (ic, slot.page, true);
            img.flush ();
            cr.save ();
            cr.translate (slot.x, slot.y);
            cr.scale (slot.scale, slot.scale);
            cr.rectangle (area.x, area.y, area.w, area.h);
            cr.clip ();
            cr.translate (area.x, area.y);
            cr.scale (1 / sc, 1 / sc);
            cr.set_source_surface (img, 0, 0);
            cr.paint ();
            cr.restore ();
        }

        private static ExportOptions separation_options (ExportOptions o) {
            var n = new ExportOptions ();
            n.ranges = o.ranges;
            n.spreads = o.spreads;
            n.bleed = o.bleed;
            n.crop_marks = true;
            n.bleed_marks = o.bleed_marks;
            n.reg_marks = true;
            n.page_info = o.page_info;
            n.color_bars = o.color_bars;
            n.marks_offset = o.marks_offset;
            n.impose = o.impose;
            n.sheet_w = o.sheet_w;
            n.sheet_h = o.sheet_h;
            n.rows = o.rows;
            n.cols = o.cols;
            n.gap = o.gap;
            n.step_repeat = o.step_repeat;
            n.tile_scale = o.tile_scale;
            n.tile_overlap = o.tile_overlap;
            return n;
        }

        public static Gee.ArrayList<string> selected_plates (Publication pub, ExportOptions opts) {
            var used = plates (pub);
            if (opts.plates.size == 0) return used;
            var list = new Gee.ArrayList<string> ();
            foreach (string p in used) if (opts.plates.contains (p)) list.add (p);
            return list;
        }

        public static void draw_plate_label (Cairo.Context cr, Sheet sh, string label) {
            var layout = new Pango.Layout (TextEngine.context ());
            var fd = new Pango.FontDescription ();
            fd.set_family ("Inter");
            fd.set_absolute_size (7 * Pango.SCALE);
            layout.set_font_description (fd);
            layout.set_text (label, -1);
            cr.save ();
            cr.set_source_rgb (0, 0, 0);
            cr.move_to (4, 3);
            Pango.cairo_show_layout (cr, layout);
            cr.restore ();
        }

        public static int export_separations (Publication pub, ExportOptions opts, string path) throws Error {
            var o = separation_options (opts);
            var inks = selected_plates (pub, opts);
            if (inks.size == 0) throw new FormatError.INVALID (_("There are no plates to export."));
            var probe = new Exporter (pub, o);
            var sheets = probe.sheets ();
            if (sheets.size == 0) throw new FormatError.INVALID (_("There are no pages to export."));
            var exporters = new Gee.ArrayList<Exporter> ();
            foreach (string ink in inks) exporters.add (new Exporter (plate_publication (pub, ink), o));
            string tmp = temp_path ();
            int pages = 0;
            try {
                var surf = new Cairo.PdfSurface (tmp, sheets[0].w, sheets[0].h);
                surf.restrict_to_version (Cairo.PdfVersion.VERSION_1_4);
                set_metadata (surf, pub);
                var cr = new Cairo.Context (surf);
                for (int s = 0; s < sheets.size; s++) {
                    var sh = sheets[s];
                    string name = o.impose == ImposeMode.NONE && sh.slots.size == 1 ? _("Page %s").printf (pub.page_label (sh.slots[0].page)) : (sh.label != "" ? sh.label : _("Sheet %d").printf (s + 1));
                    for (int i = 0; i < inks.size; i++) {
                        surf.set_size (sh.w, sh.h);
                        string label = "%s  %s".printf (name, inks[i]);
                        surf.set_page_label (label);
                        exporters[i].draw_sheet (cr, sh);
                        draw_plate_label (cr, sh, label);
                        cr.show_page ();
                        pages++;
                    }
                }
                surf.finish ();
                if (surf.status () != Cairo.Status.SUCCESS) throw new FileError.FAILED (_("Could not write the PDF: %s").printf (surf.status ().to_string ()));
                uint8[] data;
                FileUtils.get_data (tmp, out data);
                var all_boxes = boxes (probe, sheets);
                var per_page = new Gee.ArrayList<SheetBoxes> ();
                foreach (var b in all_boxes) for (int i = 0; i < inks.size; i++) per_page.add (b);
                var pp = new PdfPrepress (null, ColorManager.for_settings (pub.settings));
                pp.standard = ColorMode.RGB;
                pp.gray_plates = true;
                pp.title = pub.meta.title;
                pp.boxes = per_page;
                FileUtils.set_data (path, pp.process (data));
            } finally {
                FileUtils.unlink (tmp);
            }
            return pages;
        }
    }
}
