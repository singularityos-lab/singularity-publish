namespace Singularity.Apps.Publish {

    public class LayoutCache {
        public Publication pub;
        public int record = -1;
        private Gee.HashMap<string, StoryResult> stories = new Gee.HashMap<string, StoryResult> ();
        private Gee.HashMap<string, FrameResult> cells = new Gee.HashMap<string, FrameResult> ();
        private TextEngine engine;

        public LayoutCache (Publication pub, int record = -1) {
            this.pub = pub;
            this.record = record;
            engine = new TextEngine (pub);
            engine.record = record;
            engine.alpha_rows = alpha_rows;
            engine.running = running_header;
            engine.xref_lookup = xref_lookup;
        }

        private class AnchorInfo {
            public int page = -1;
            public string number = "";
            public string text = "";
        }

        private Gee.HashMap<string, AnchorInfo> anchors = new Gee.HashMap<string, AnchorInfo> ();
        private bool in_xref = false;

        private void record_anchors (StoryResult res) {
            var st = res.story;
            foreach (var fr in res.frames) {
                foreach (var l in fr.lines) {
                    if (l.is_drop || !l.para_first || l.para < 0 || l.para >= st.paras.size) continue;
                    var p = st.paras[l.para];
                    if (p.anchor == "") continue;
                    var info = new AnchorInfo ();
                    info.page = fr.page_index;
                    info.text = p.text ().replace (OBJ_STR, "").replace ("\u2028", " ").strip ();
                    if (l.build.prefix_bytes > 0) info.number = l.build.text.substring (0, l.build.prefix_bytes).strip ();
                    anchors[p.anchor] = info;
                }
            }
        }

        private bool xref_lookup (string anchor, out int page, out string number, out string text) {
            page = -1;
            number = "";
            text = "";
            if (!anchors.has_key (anchor) && !in_xref) {
                in_xref = true;
                foreach (var st in pub.stories.values) {
                    bool here = false;
                    foreach (var p in st.paras) if (p.anchor == anchor) here = true;
                    if (!here || pub.thread_frames (st.id).size == 0) continue;
                    record_anchors (engine.layout_story (st.id));
                    break;
                }
                in_xref = false;
            }
            if (!anchors.has_key (anchor)) return false;
            var info = anchors[anchor];
            page = info.page;
            number = info.number;
            text = info.text;
            return true;
        }

        private bool in_running = false;

        private string? running_header (string style, bool last, int page_index) {
            if (in_running || page_index < 0 || page_index >= pub.pages.size) return null;
            in_running = true;
            string? found = null;
            var page = pub.pages[page_index];
            var frames = new Gee.ArrayList<TextFrame> ();
            foreach (var it in page.items) {
                var t = it as TextFrame;
                if (t != null) frames.add (t);
            }
            frames.sort ((a, b) => {
                if (Math.fabs (a.y - b.y) > 1) return a.y < b.y ? -1 : 1;
                return a.x < b.x ? -1 : (a.x > b.x ? 1 : 0);
            });
            foreach (var t in frames) {
                var res = story (t.story);
                var fr = res.frame_result (t.id);
                if (fr == null) continue;
                var st = pub.story (t.story);
                foreach (var l in fr.lines) {
                    if (l.para < 0 || l.para >= st.paras.size) continue;
                    var para = st.paras[l.para];
                    if (para.style != style) continue;
                    found = para.text ().replace ("\u2028", " ").strip ();
                    if (!last) break;
                }
                if (found != null && !last) break;
            }
            in_running = false;
            return found;
        }

        private Gee.ArrayList<double?>? alpha_rows (ImageFrame f, out double y0, out double step) {
            return ImageStore.get_default ().alpha_rows (pub, f, out y0, out step);
        }

        public TextEngine get_engine () {
            return engine;
        }

        public void invalidate () {
            stories.clear ();
            cells.clear ();
            anchors.clear ();
            engine.reset_notes ();
        }

        public void invalidate_story (int id) {
            var before = engine.note_map ();
            var before_end = engine.endnote_map ();
            engine.reset_notes ();
            var after = engine.note_map ();
            var after_end = engine.endnote_map ();
            bool same = before.size == after.size && before_end.size == after_end.size;
            if (same) foreach (var e in after.entries) if (!before.has_key (e.key) || before[e.key] != e.value) same = false;
            if (same) foreach (var e in after_end.entries) if (!before_end.has_key (e.key) || before_end[e.key] != e.value) same = false;
            if (!same) {
                stories.clear ();
                cells.clear ();
                return;
            }
            var dead = new Gee.ArrayList<string> ();
            var ids = new Gee.HashSet<int> ();
            ids.add (id);
            if (pub.stories.has_key (id)) foreach (var p in pub.stories[id].paras) if (p.anchor != "") anchors.unset (p.anchor);
            foreach (var st in pub.stories.values) {
                bool refers = false;
                foreach (var p in st.paras) foreach (var r in p.runs) if (r.field.has_prefix (Fields.XREF_PREFIX)) refers = true;
                if (refers) ids.add (st.id);
            }
            foreach (var k in stories.keys) {
                foreach (int sid in ids) if (k.has_prefix ("%d:".printf (sid))) dead.add (k);
            }
            foreach (var k in dead) stories.unset (k);
            cells.clear ();
        }

        public StoryResult story (int id) {
            string key = "%d:body".printf (id);
            if (!stories.has_key (key)) {
                var res = engine.layout_story (id);
                stories[key] = res;
                record_anchors (res);
            }
            return stories[key];
        }

        public StoryResult master_story (int id, int page_index) {
            string key = "%d:page%d".printf (id, page_index);
            if (!stories.has_key (key)) stories[key] = engine.layout_story (id, page_index);
            return stories[key];
        }

        public FrameResult? frame (TextFrame f, bool master_instance, int page_index) {
            var res = master_instance ? master_story (f.story, page_index) : story (f.story);
            return res.frame_result (f.id);
        }

        public FrameResult cell (Story s, double w, double h, int page_index) {
            string key = "%d:%s:%s:%d".printf (s.id, XmlOut.num (w), XmlOut.num (h), page_index);
            if (!cells.has_key (key)) cells[key] = engine.layout_box (s, w, h, page_index);
            return cells[key];
        }
    }

    public class LinkArea {
        public string link;
        public Rect rect;

        public LinkArea (string link, Rect rect) {
            this.link = link;
            this.rect = rect;
        }
    }

    public abstract class GlyphSink {
        public abstract bool line (Cairo.Context cr, Pango.LayoutLine line, double x, double y);
    }

    public class SolidOutput : ColorOutput {
        public Rgba color;

        public override Rgba map (Publication pub, string spec, Rgba screen) {
            if (spec == ColorRef.NONE) return screen;
            return Rgba (color.r, color.g, color.b, color.a * screen.a);
        }

        public override Rgba map_raw (Rgba c) {
            return Rgba (color.r, color.g, color.b, color.a * c.a);
        }
    }

    public class RenderOptions {
        public bool print = false;
        public bool frame_edges = false;
        public bool overset_marks = true;
        public bool placeholders = true;
        public bool guides = false;
        public bool links = false;
        public Gee.HashMap<int, int>? page_map = null;
        public Gee.ArrayList<LinkArea>? link_sink = null;
        public GlyphSink? glyph_sink = null;
        public int highlight_story = -1;
        public Gee.HashSet<int>? skip = null;
        public Gee.HashSet<int>? selected = null;
        public bool tagged = false;
        public Gee.ArrayList<string>? alt_sink = null;
    }

    public class Renderer {
        public Publication pub;
        public LayoutCache cache;
        public RenderOptions opts = new RenderOptions ();

        public Renderer (Publication pub, LayoutCache? cache = null) {
            this.pub = pub;
            this.cache = cache ?? new LayoutCache (pub);
        }

        public static void set_rgba (Cairo.Context cr, Rgba c, double alpha = 1) {
            cr.set_source_rgba (c.r, c.g, c.b, c.a * alpha);
        }

        public void set_color (Cairo.Context cr, string spec, double alpha = 1) {
            set_rgba (cr, pub.resolve (spec), alpha);
        }

        public void overprint (bool on) {
            if (pub.output != null) pub.output.overprint = on;
        }

        public Gee.ArrayList<Item> ordered (Gee.ArrayList<Item> items) {
            var list = new Gee.ArrayList<Item> ();
            list.add_all (items);
            var idx = new Gee.HashMap<Item, int> ();
            for (int i = 0; i < items.size; i++) idx[items[i]] = i;
            list.sort ((a, b) => {
                int la = pub.layer_index (a.layer), lb = pub.layer_index (b.layer);
                if (la != lb) return la - lb;
                int za = a.wrap == WrapMode.BEHIND ? 0 : (a.wrap == WrapMode.IN_FRONT ? 2 : 1);
                int zb = b.wrap == WrapMode.BEHIND ? 0 : (b.wrap == WrapMode.IN_FRONT ? 2 : 1);
                if (za != zb) return za - zb;
                return idx[a] - idx[b];
            });
            return list;
        }

        public bool item_visible (Item it) {
            if (it.hidden) return false;
            if (opts.skip != null && opts.skip.contains (it.id)) return false;
            if (it.show_when != null && pub.merge.active ()) {
                int rec = cache.record >= 0 ? cache.record : pub.merge.preview;
                if (rec >= 0 && !Merge.shows (pub, it, rec)) return false;
            }
            var l = pub.layer (it.layer);
            if (l != null) {
                if (!l.visible) return false;
                if (opts.print && !l.printable) return false;
            }
            if (opts.print && it.nonprinting) return false;
            return true;
        }

        public void draw_page (Cairo.Context cr, int page_index, bool paper = true) {
            if (page_index < 0 || page_index >= pub.pages.size) return;
            var pg = pub.pages[page_index];
            if (paper) {
                cr.set_source_rgb (1, 1, 1);
                cr.rectangle (0, 0, pub.page_w (page_index), pub.page_h (page_index));
                cr.fill ();
            }
            var all = new Gee.ArrayList<Item> ();
            var masters = new Gee.HashSet<Item> ();
            foreach (var it in pub.master_items_for (page_index)) {
                all.add (it);
                masters.add (it);
            }
            foreach (var it in pg.items) all.add (it);
            var list = ordered (all);
            foreach (var it in list) {
                if (!item_visible (it)) continue;
                draw_item (cr, it, masters.contains (it), page_index);
            }
        }

        public void draw_master (Cairo.Context cr, MasterPage m, bool left) {
            cr.set_source_rgb (1, 1, 1);
            cr.rectangle (0, 0, pub.settings.width, pub.settings.height);
            cr.fill ();
            var all = new Gee.ArrayList<Item> ();
            foreach (var parent in pub.master_chain (m.based_on)) all.add_all (parent.items_for (left && pub.settings.facing));
            all.add_all (m.items_for (left && pub.settings.facing));
            foreach (var it in ordered (all)) {
                if (!item_visible (it)) continue;
                draw_item (cr, it, false, -1);
            }
        }

        public static void text_space (Cairo.Context cr, Item it) {
            var t = it as TextFrame;
            if (t != null && t.vertical) {
                cr.translate (t.w, 0);
                cr.rotate (Math.PI / 2);
            }
        }

        public static Point to_text_space (Item it, Point local) {
            var t = it as TextFrame;
            if (t != null && t.vertical) return Point (local.y, t.w - local.x);
            return local;
        }

        public void transform (Cairo.Context cr, Item it) {
            cr.translate (it.x + it.w / 2, it.y + it.h / 2);
            if (it.rotation != 0) cr.rotate (it.rotation * Math.PI / 180);
            cr.scale (it.flip_h ? -1 : 1, it.flip_v ? -1 : 1);
            cr.translate (-it.w / 2, -it.h / 2);
        }

        public static void round_rect (Cairo.Context cr, double x, double y, double w, double h, double r) {
            r = double.min (r, double.min (w, h) / 2);
            if (r <= 0) {
                cr.rectangle (x, y, w, h);
                return;
            }
            cr.new_sub_path ();
            cr.arc (x + w - r, y + r, r, -Math.PI / 2, 0);
            cr.arc (x + w - r, y + h - r, r, 0, Math.PI / 2);
            cr.arc (x + r, y + h - r, r, Math.PI / 2, Math.PI);
            cr.arc (x + r, y + r, r, Math.PI, 3 * Math.PI / 2);
            cr.close_path ();
        }

        public void shape_path (Cairo.Context cr, Item it) {
            double w = it.w, h = it.h;
            var wa = it as WordArtItem;
            if (wa != null) {
                FxRender.wordart_path (cr, wa);
                return;
            }
            var im = it as ImageFrame;
            if (im != null && im.clip_shape != "" && im.clip_shape != "ellipse") {
                ShapeLib.path (cr, im.clip_shape, w, h);
                return;
            }
            var s = it as ShapeItem;
            if (s != null && s.shape == ShapeKind.PATH && s.path_d != "") {
                SvgPath.trace (cr, s.path_d, w, h);
                cr.set_fill_rule (s.even_odd ? Cairo.FillRule.EVEN_ODD : Cairo.FillRule.WINDING);
                return;
            }
            if (s != null && s.shape != ShapeKind.RECT && s.shape != ShapeKind.ELLIPSE) {
                var pts = s.local_points ();
                if (pts.size == 0) return;
                cr.move_to (pts[0].x, pts[0].y);
                for (int i = 1; i < pts.size; i++) cr.line_to (pts[i].x, pts[i].y);
                if (s.shape != ShapeKind.LINE && (s.shape != ShapeKind.PATH || s.closed)) cr.close_path ();
                return;
            }
            if (it.shape_ellipse || (s != null && s.shape == ShapeKind.ELLIPSE) || (im != null && im.clip_shape == "ellipse")) {
                cr.save ();
                cr.translate (w / 2, h / 2);
                cr.scale (double.max (w / 2, 0.01), double.max (h / 2, 0.01));
                cr.arc (0, 0, 1, 0, 2 * Math.PI);
                cr.restore ();
                cr.close_path ();
                return;
            }
            double r = double.min (it.corner_radius, double.min (w, h) / 2);
            if (r <= 0 || it.corner == CornerKind.NONE) {
                cr.rectangle (0, 0, w, h);
                return;
            }
            switch (it.corner) {
                case CornerKind.BEVEL:
                    cr.move_to (r, 0);
                    cr.line_to (w - r, 0);
                    cr.line_to (w, r);
                    cr.line_to (w, h - r);
                    cr.line_to (w - r, h);
                    cr.line_to (r, h);
                    cr.line_to (0, h - r);
                    cr.line_to (0, r);
                    cr.close_path ();
                    break;
                case CornerKind.INSET:
                    cr.move_to (r, 0);
                    cr.line_to (w - r, 0);
                    cr.line_to (w - r, r);
                    cr.line_to (w, r);
                    cr.line_to (w, h - r);
                    cr.line_to (w - r, h - r);
                    cr.line_to (w - r, h);
                    cr.line_to (r, h);
                    cr.line_to (r, h - r);
                    cr.line_to (0, h - r);
                    cr.line_to (0, r);
                    cr.line_to (r, r);
                    cr.close_path ();
                    break;
                case CornerKind.INVERSE_ROUNDED:
                    cr.move_to (r, 0);
                    cr.line_to (w - r, 0);
                    cr.arc_negative (w, 0, r, Math.PI, Math.PI / 2);
                    cr.line_to (w, h - r);
                    cr.arc_negative (w, h, r, 3 * Math.PI / 2, Math.PI);
                    cr.line_to (r, h);
                    cr.arc_negative (0, h, r, 0, 3 * Math.PI / 2);
                    cr.line_to (0, r);
                    cr.arc_negative (0, 0, r, Math.PI / 2, 0);
                    cr.close_path ();
                    break;
                default:
                    round_rect (cr, 0, 0, w, h, r);
                    break;
            }
        }

        public void apply_fill (Cairo.Context cr, Fill f, double w, double h) {
            switch (f.kind) {
                case FillKind.SOLID:
                    set_color (cr, f.color);
                    break;
                case FillKind.LINEAR:
                case FillKind.RADIAL:
                    Cairo.Pattern pat;
                    if (f.kind == FillKind.LINEAR) {
                        double a = f.angle * Math.PI / 180;
                        double dx = Math.cos (a), dy = Math.sin (a);
                        double half = (Math.fabs (dx) * w + Math.fabs (dy) * h) / 2;
                        pat = new Cairo.Pattern.linear (w / 2 - dx * half, h / 2 - dy * half, w / 2 + dx * half, h / 2 + dy * half);
                    } else {
                        pat = new Cairo.Pattern.radial (w / 2, h / 2, 0, w / 2, h / 2, Math.sqrt (w * w + h * h) / 2);
                    }
                    foreach (var s in f.stops) {
                        var c = pub.resolve (s.color);
                        pat.add_color_stop_rgba (s.offset, c.r, c.g, c.b, c.a * s.opacity);
                    }
                    cr.set_source (pat);
                    break;
                case FillKind.PATTERN:
                    FxRender.set_pattern_source (this, cr, f);
                    break;
                case FillKind.TEXTURE:
                case FillKind.PICTURE:
                    if (!FxRender.set_raster_fill (this, cr, f, w, h)) cr.set_source_rgba (0, 0, 0, 0);
                    break;
                default:
                    cr.set_source_rgba (0, 0, 0, 0);
                    break;
            }
        }

        public void apply_stroke (Cairo.Context cr, Stroke s) {
            set_color (cr, s.color);
            cr.set_line_width (s.width);
            double w = double.max (s.width, 0.5);
            switch (s.dash) {
                case DashKind.DASH: cr.set_dash ({ w * 4, w * 2 }, 0); break;
                case DashKind.DOT: cr.set_dash ({ w, w * 1.5 }, 0); break;
                case DashKind.DASH_DOT: cr.set_dash ({ w * 4, w * 1.5, w, w * 1.5 }, 0); break;
                default: cr.set_dash (null, 0); break;
            }
            cr.set_line_cap (s.cap == 1 ? Cairo.LineCap.ROUND : (s.cap == 2 ? Cairo.LineCap.SQUARE : Cairo.LineCap.BUTT));
            cr.set_line_join (s.join == 1 ? Cairo.LineJoin.ROUND : (s.join == 2 ? Cairo.LineJoin.BEVEL : Cairo.LineJoin.MITER));
        }

        private void draw_shadow (Cairo.Context cr, Item it, bool master, int page_index) {
            var sh = it.shadow;
            if (sh.blur < 0.01 && !(it is ImageFrame || it is TableItem || it.fill.visible ())) {
                var saved_out = pub.output;
                var solid = new SolidOutput ();
                var c = pub.resolve (sh.color);
                solid.color = Rgba (c.r, c.g, c.b, sh.opacity);
                pub.output = solid;
                var saved_marks = opts.overset_marks;
                opts.overset_marks = false;
                cr.save ();
                cr.translate (sh.dx, sh.dy);
                draw_content (cr, it, master, page_index, false);
                cr.restore ();
                opts.overset_marks = saved_marks;
                pub.output = saved_out;
                return;
            }
            if (sh.blur < 0.01) {
                cr.save ();
                cr.translate (sh.dx, sh.dy);
                set_color (cr, sh.color, sh.opacity);
                if (it is ImageFrame || it is TableItem || it.fill.visible ()) {
                    shape_path (cr, it);
                    cr.fill ();
                }
                if (it.stroke.visible ()) {
                    shape_path (cr, it);
                    cr.set_line_width (it.stroke.width);
                    cr.stroke ();
                }
                cr.restore ();
                return;
            }
            double sx = 1, sy = 1;
            cr.user_to_device_distance (ref sx, ref sy);
            double scale = double.min (4, double.max (0.5, Math.sqrt (Math.fabs (sx * sy))));
            if (opts.print) scale = double.max (scale, 300.0 / 72.0);
            double pad = sh.blur * 2 + 2;
            int pw = (int) Math.ceil ((it.w + pad * 2) * scale), ph = (int) Math.ceil ((it.h + pad * 2) * scale);
            if (pw <= 0 || ph <= 0 || pw > 6000 || ph > 6000) return;
            var surf = new Cairo.ImageSurface (Cairo.Format.A8, pw, ph);
            var sc = new Cairo.Context (surf);
            sc.scale (scale, scale);
            sc.translate (pad, pad);
            if (it is ImageFrame || it is TableItem || it.fill.visible ()) {
                shape_path (sc, it);
                sc.set_source_rgba (0, 0, 0, 1);
                sc.fill ();
            } else {
                var img = new Cairo.ImageSurface (Cairo.Format.ARGB32, pw, ph);
                var ic = new Cairo.Context (img);
                ic.scale (scale, scale);
                ic.translate (pad, pad);
                var saved = opts.overset_marks;
                opts.overset_marks = false;
                draw_content (ic, it, master, page_index, false);
                opts.overset_marks = saved;
                sc.set_source_surface (img, 0, 0);
                sc.paint ();
            }
            if (it.stroke.visible ()) {
                shape_path (sc, it);
                sc.set_source_rgba (0, 0, 0, 1);
                sc.set_line_width (it.stroke.width);
                sc.stroke ();
            }
            surf.flush ();
            box_blur (surf, (int) Math.round (sh.blur * scale / 2));
            cr.save ();
            cr.translate (sh.dx - pad, sh.dy - pad);
            cr.scale (1 / scale, 1 / scale);
            set_color (cr, sh.color, sh.opacity);
            cr.mask_surface (surf, 0, 0);
            cr.restore ();
        }

        public static void box_blur (Cairo.ImageSurface surf, int radius) {
            if (radius < 1) return;
            int w = surf.get_width (), h = surf.get_height (), stride = surf.get_stride ();
            unowned uint8[] d = surf.get_data ();
            var tmp = new uint8[stride * h];
            for (int pass = 0; pass < 3; pass++) {
                for (int y = 0; y < h; y++) {
                    int sum = 0;
                    int row = y * stride;
                    for (int x = -radius; x <= radius; x++) sum += d[row + x.clamp (0, w - 1)];
                    for (int x = 0; x < w; x++) {
                        tmp[row + x] = (uint8) (sum / (2 * radius + 1));
                        sum += d[row + (x + radius + 1).clamp (0, w - 1)] - d[row + (x - radius).clamp (0, w - 1)];
                    }
                }
                for (int x = 0; x < w; x++) {
                    int sum = 0;
                    for (int y = -radius; y <= radius; y++) sum += tmp[y.clamp (0, h - 1) * stride + x];
                    for (int y = 0; y < h; y++) {
                        d[y * stride + x] = (uint8) (sum / (2 * radius + 1));
                        sum += tmp[(y + radius + 1).clamp (0, h - 1) * stride + x] - tmp[(y - radius).clamp (0, h - 1) * stride + x];
                    }
                }
            }
            surf.mark_dirty ();
        }

        public string? link_attrs (string link) {
            if (link == "") return null;
            if (link.has_prefix ("page:")) {
                int pg = int.parse (link.substring (5));
                if (opts.page_map == null || !opts.page_map.has_key (pg)) return null;
                return "page=%d pos=[0 0]".printf (opts.page_map[pg]);
            }
            if (link.has_prefix ("bookmark:")) {
                var b = pub.bookmark (link.substring (9));
                if (b == null) return null;
                return "dest='%s'".printf (dest_name (b.name));
            }
            string uri = link;
            if (!uri.contains (":") && uri.contains ("@")) uri = "mailto:" + uri;
            else if (!uri.contains (":")) uri = "https://" + uri;
            return "uri='%s'".printf (uri.replace ("\\", "\\\\").replace ("'", "\\'"));
        }

        public static string dest_name (string name) {
            var sb = new StringBuilder ("bm-");
            unichar c;
            int i = 0;
            while (name.get_next_char (ref i, out c)) {
                if (c.isalnum () || c == '-' || c == '_') sb.append_unichar (c);
                else sb.append_c ('_');
            }
            return sb.str;
        }

        private void link_rect (Cairo.Context cr, string link, string attrs, double x, double y, double w, double h) {
            double x0 = x, y0 = y, x1 = x + w, y1 = y + h, x2 = x + w, y2 = y, x3 = x, y3 = y + h;
            cr.user_to_device (ref x0, ref y0);
            cr.user_to_device (ref x1, ref y1);
            cr.user_to_device (ref x2, ref y2);
            cr.user_to_device (ref x3, ref y3);
            double minx = double.min (double.min (x0, x1), double.min (x2, x3)), maxx = double.max (double.max (x0, x1), double.max (x2, x3));
            double miny = double.min (double.min (y0, y1), double.min (y2, y3)), maxy = double.max (double.max (y0, y1), double.max (y2, y3));
            if (opts.link_sink != null) {
                opts.link_sink.add (new LinkArea (link, Rect (minx, miny, maxx - minx, maxy - miny)));
                return;
            }
            cr.tag_begin (Cairo.TAG_LINK, "%s rect=[%s %s %s %s]".printf (attrs, XmlOut.num (minx), XmlOut.num (miny), XmlOut.num (maxx - minx), XmlOut.num (maxy - miny)));
            cr.tag_end (Cairo.TAG_LINK);
        }

        public void draw_item (Cairo.Context cr, Item it, bool master, int page_index) {
            cr.save ();
            transform (cr, it);
            bool group_alpha = it.opacity < 0.999;
            if (group_alpha) cr.push_group ();
            var fx = it.effects;
            if (fx.glow) FxRender.draw_glow (this, cr, it);
            if (it.shadow.enabled) draw_shadow (cr, it, master, page_index);
            if (fx.reflection) FxRender.draw_reflection (this, cr, it, (c) => draw_content (c, it, master, page_index, false));
            if (fx.soft_edges > 0.01) FxRender.draw_soft_content (this, cr, it, (c) => draw_content (c, it, master, page_index, true));
            else draw_content (cr, it, master, page_index, true);
            if (fx.bevel) FxRender.draw_bevel (this, cr, it);
            if (it.border_art.visible () && !(it is GroupItem)) {
                overprint (it.overprint_stroke);
                FxRender.draw_border_art (this, cr, it);
            }
            if (group_alpha) {
                cr.pop_group_to_source ();
                cr.paint_with_alpha (it.opacity);
            }
            if (opts.links && it.link != "") {
                string? attrs = link_attrs (it.link);
                if (attrs != null || opts.link_sink != null) link_rect (cr, it.link, attrs ?? "", 0, 0, it.w, it.h);
            }
            cr.restore ();
        }

        public void draw_content (Cairo.Context cr, Item it, bool master, int page_index, bool decorations) {
            switch (it.kind) {
                case ItemKind.GROUP:
                    var g = (GroupItem) it;
                    cr.translate (-g.x, -g.y);
                    foreach (var c in ordered (g.children)) if (item_visible (c)) draw_item (cr, c, master, page_index);
                    break;
                case ItemKind.IMAGE:
                    bool fig = opts.tagged && !it.alt_decorative;
                    if (fig) {
                        cr.tag_begin ("Figure", "");
                        if (opts.alt_sink != null) opts.alt_sink.add (it.alt_text);
                    }
                    draw_image (cr, (ImageFrame) it, decorations);
                    if (fig) cr.tag_end ("Figure");
                    break;
                case ItemKind.TABLE:
                    if (opts.tagged) cr.tag_begin ("Table", "");
                    draw_table (cr, (TableItem) it, page_index);
                    if (opts.tagged) cr.tag_end ("Table");
                    break;
                case ItemKind.TEXT:
                    draw_text_frame (cr, (TextFrame) it, master, page_index, decorations);
                    break;
                default:
                    draw_shape (cr, (ShapeItem) it);
                    break;
            }
        }

        private void draw_shape (Cairo.Context cr, ShapeItem s) {
            overprint (s.overprint_fill);
            if (s is WordArtItem) {
                if (s.fill.visible ()) {
                    shape_path (cr, s);
                    apply_fill (cr, s.fill, s.w, s.h);
                    cr.fill ();
                }
                overprint (s.overprint_stroke);
                if (s.stroke.visible ()) {
                    shape_path (cr, s);
                    apply_stroke (cr, s.stroke);
                    cr.set_line_join (Cairo.LineJoin.ROUND);
                    cr.stroke ();
                }
                return;
            }
            if (s.shape != ShapeKind.LINE && s.fill.visible ()) {
                shape_path (cr, s);
                apply_fill (cr, s.fill, s.w, s.h);
                cr.fill ();
            }
            overprint (s.overprint_stroke);
            if (s.stroke.visible ()) {
                shape_path (cr, s);
                apply_stroke (cr, s.stroke);
                cr.stroke ();
                if (s.shape == ShapeKind.LINE) draw_arrows (cr, s);
            }
        }

        private void draw_arrows (Cairo.Context cr, ShapeItem s) {
            var pts = s.local_points ();
            if (pts.size < 2) return;
            double size = double.max (6, s.stroke.width * 4);
            set_color (cr, s.stroke.color);
            cr.set_dash (null, 0);
            if (s.stroke.arrow_end > 0) arrow_head (cr, pts[0], pts[1], size, s.stroke.arrow_end);
            if (s.stroke.arrow_start > 0) arrow_head (cr, pts[1], pts[0], size, s.stroke.arrow_start);
        }

        private static void arrow_head (Cairo.Context cr, Point from, Point to, double size, int kind) {
            double a = Math.atan2 (to.y - from.y, to.x - from.x);
            cr.save ();
            cr.translate (to.x, to.y);
            cr.rotate (a);
            if (kind == 2) {
                cr.arc (0, 0, size / 2.5, 0, 2 * Math.PI);
                cr.fill ();
            } else {
                cr.move_to (0, 0);
                cr.line_to (-size, -size / 2.2);
                cr.line_to (-size, size / 2.2);
                cr.close_path ();
                cr.fill ();
            }
            cr.restore ();
        }

        private void draw_frame_box (Cairo.Context cr, Item it) {
            overprint (it.overprint_fill);
            if (it.fill.visible ()) {
                shape_path (cr, it);
                apply_fill (cr, it.fill, it.w, it.h);
                cr.fill ();
            }
        }

        private void draw_frame_stroke (Cairo.Context cr, Item it) {
            overprint (it.overprint_stroke);
            if (it.stroke.visible ()) {
                shape_path (cr, it);
                apply_stroke (cr, it.stroke);
                cr.stroke ();
            }
        }

        public void draw_image (Cairo.Context cr, ImageFrame f, bool decorations) {
            draw_frame_box (cr, f);
            var src = merge_source (f);
            var inf = ImageStore.get_default ().info (pub, src);
            if (inf != null && inf.surface != null) {
                cr.save ();
                shape_path (cr, f);
                cr.clip ();
                var pl = ImageStore.place (src, inf);
                cr.translate (pl.ox, pl.oy);
                cr.scale (pl.sx, pl.sy);
                if (inf.vector && pub.output == null && !f.adjusted ()) {
                    var art = ImageStore.get_default ().vector (pub, src);
                    if (art != null) {
                        cr.scale (inf.dpi / 72.0, inf.dpi / 72.0);
                        art.render (cr, src.pdf_page);
                        cr.restore ();
                        draw_frame_stroke (cr, f);
                        return;
                    }
                }
                if (f.clip_path) {
                    var paths = ImageStore.get_default ().image_paths (pub, src);
                    var path = paths != null ? paths.preferred () : null;
                    if (path != null) {
                        cr.new_path ();
                        path.trace (cr, inf.width, inf.height);
                        cr.clip ();
                    }
                }
                Cairo.ImageSurface adj = f.adjusted () ? FxRender.adjust (pub, inf.surface, f) : inf.surface;
                Cairo.Surface surf = adj;
                if (pub.output != null) {
                    var mapped = pub.output.map_image (adj);
                    if (mapped != null) surf = mapped;
                }
                cr.set_source_surface (surf, 0, 0);
                var pat = cr.get_source ();
                pat.set_filter (Cairo.Filter.GOOD);
                cr.paint ();
                cr.restore ();
            } else if (!opts.print && opts.placeholders && decorations) {
                cr.save ();
                bool missing = f.has_image ();
                cr.set_source_rgba (missing ? 0.85 : 0.55, missing ? 0.25 : 0.55, missing ? 0.2 : 0.6, 0.6);
                cr.set_line_width (0.75);
                cr.rectangle (0, 0, f.w, f.h);
                cr.move_to (0, 0);
                cr.line_to (f.w, f.h);
                cr.move_to (f.w, 0);
                cr.line_to (0, f.h);
                cr.stroke ();
                cr.restore ();
            }
            draw_frame_stroke (cr, f);
        }

        public ImageFrame merge_source (ImageFrame f) {
            if (f.merge_field == "") return f;
            int rec = cache.record >= 0 ? cache.record : pub.merge.preview;
            if (rec < 0) return f;
            string v = Merge.image_path (pub, pub.merge.value (rec, f.merge_field));
            if (v == "") return f;
            var c = (ImageFrame) f.clone ();
            c.link = v;
            c.media = "";
            c.link_stamp = "";
            return c;
        }

        private void draw_tagged (Cairo.Context cr, TextFrame t, FrameResult fr) {
            var st = pub.story (t.story);
            int i = 0;
            while (i < fr.lines.size) {
                int para = fr.lines[i].para;
                var group = new Gee.ArrayList<LaidLine> ();
                while (i < fr.lines.size && fr.lines[i].para == para) group.add (fr.lines[i++]);
                string role = para >= 0 && para < st.paras.size ? PdfFinish.role_for (pub, st.paras[para]) : "P";
                cr.tag_begin (role, "");
                draw_lines (cr, group);
                cr.tag_end (role);
            }
            foreach (var n in fr.notes) {
                cr.tag_begin ("Note", "");
                var one = new FrameResult (null);
                one.notes.add (n);
                draw_notes (cr, one);
                cr.tag_end ("Note");
            }
        }

        public void draw_notes (Cairo.Context cr, FrameResult fr) {
            if (fr.notes.size == 0) return;
            var o = pub.footnotes;
            var done = new Gee.HashSet<int> ();
            foreach (var n in fr.notes) {
                if (o.rule && done.add (n.column) && o.rule_weight > 0) {
                    double ry = n.y - o.space_before / 2;
                    foreach (var m in fr.notes) if (m.column == n.column) ry = double.min (ry, m.y - o.space_before / 2);
                    cr.save ();
                    set_color (cr, o.rule_color);
                    cr.set_line_width (o.rule_weight);
                    cr.move_to (n.x, ry);
                    cr.line_to (n.x + double.min (o.rule_length, n.w), ry);
                    cr.stroke ();
                    cr.restore ();
                }
                cr.save ();
                cr.translate (n.x, n.y);
                draw_lines (cr, n.box.lines);
                cr.restore ();
            }
        }

        public void draw_text_frame (Cairo.Context cr, TextFrame t, bool master, int page_index, bool decorations) {
            draw_frame_box (cr, t);
            var fr = cache.frame (t, master, page_index);
            overprint (t.overprint_fill);
            if (fr != null) {
                cr.save ();
                text_space (cr, t);
                if (opts.tagged) draw_tagged (cr, t, fr);
                else {
                    draw_lines (cr, fr.lines);
                    draw_notes (cr, fr);
                }
                cr.restore ();
            }
            draw_frame_stroke (cr, t);
            if (!opts.print && decorations) {
                var res = master ? cache.master_story (t.story, page_index) : cache.story (t.story);
                var frames = res.frames;
                bool last = frames.size > 0 && frames[frames.size - 1].frame == t;
                if (opts.overset_marks && last && res.overset && (opts.selected == null || !opts.selected.contains (t.id))) draw_overset_mark (cr, t);
                if (opts.frame_edges) {
                    cr.save ();
                    cr.set_source_rgba (0.3, 0.5, 0.9, 0.55);
                    cr.set_line_width (0.5);
                    cr.set_dash ({ 2, 2 }, 0);
                    cr.rectangle (0, 0, t.w, t.h);
                    cr.stroke ();
                    if (t.columns > 1) {
                        double iw = t.w - t.inset_left - t.inset_right;
                        double cw = (iw - t.gutter * (t.columns - 1)) / t.columns;
                        for (int i = 1; i < t.columns; i++) {
                            double x = t.inset_left + i * cw + (i - 1) * t.gutter;
                            cr.rectangle (x, t.inset_top, t.gutter, t.h - t.inset_top - t.inset_bottom);
                            cr.stroke ();
                        }
                    }
                    cr.restore ();
                }
            }
        }

        public static void draw_overset_mark (Cairo.Context cr, Item t) {
            double s = 9;
            double x = t.w - s - 1, y = t.h - s - 1;
            cr.save ();
            cr.set_dash (null, 0);
            cr.set_source_rgb (1, 1, 1);
            cr.rectangle (x, y, s, s);
            cr.fill ();
            cr.set_source_rgb (0.86, 0.1, 0.1);
            cr.set_line_width (1);
            cr.rectangle (x + 0.5, y + 0.5, s - 1, s - 1);
            cr.stroke ();
            cr.move_to (x + s / 2, y + 2);
            cr.line_to (x + s / 2, y + s - 2);
            cr.move_to (x + 2, y + s / 2);
            cr.line_to (x + s - 2, y + s / 2);
            cr.stroke ();
            cr.restore ();
        }

        private void span_range (LaidLine l, Span sp, double x, out double x0, out double x1) {
            int a = int.max (sp.start, l.disp_start) - l.window, e = int.min (sp.end, l.disp_end) - l.window;
            int len = l.layout.get_text ().length;
            a = a.clamp (0, len);
            e = e.clamp (0, len);
            int xa, xb;
            l.line ().index_to_x (a, false, out xa);
            l.line ().index_to_x (e, false, out xb);
            x0 = x + double.min (xa, xb) / (double) Pango.SCALE * l.hscale;
            x1 = x + double.max (xa, xb) / (double) Pango.SCALE * l.hscale;
        }

        public void draw_lines (Cairo.Context cr, Gee.ArrayList<LaidLine> lines) {
            foreach (var l in lines) {
                if (l.para_first && !l.is_drop) draw_rule (cr, l, true);
                if (l.para_last && !l.is_drop) draw_rule (cr, l, false);
                double x = l.x + (l.is_drop ? 0 : l.x_off);
                var fx_spans = new Gee.ArrayList<Span> ();
                foreach (var sp in l.build.spans) {
                    if (sp.end <= l.disp_start || sp.start >= l.disp_end) continue;
                    if (sp.fmt.has_effects ()) fx_spans.add (sp);
                }
                foreach (var sp in fx_spans) {
                    double x0, x1;
                    span_range (l, sp, x, out x0, out x1);
                    if (x1 - x0 > 0.01) FxRender.text_effects_under (this, cr, l, x, sp.fmt, x0, x1);
                }
                if (Math.fabs (l.hscale - 1) > 1e-6) {
                    cr.save ();
                    cr.translate (x, l.baseline);
                    cr.scale (l.hscale, 1);
                    cr.move_to (0, 0);
                    if (opts.glyph_sink == null || !opts.glyph_sink.line (cr, l.line (), 0, 0)) Pango.cairo_show_layout_line (cr, l.line ());
                    cr.restore ();
                } else {
                    cr.move_to (x, l.baseline);
                    if (opts.glyph_sink == null || !opts.glyph_sink.line (cr, l.line (), x, l.baseline)) Pango.cairo_show_layout_line (cr, l.line ());
                }
                foreach (var sp in fx_spans) {
                    double x0, x1;
                    span_range (l, sp, x, out x0, out x1);
                    if (x1 - x0 > 0.01) FxRender.text_effects_over (this, cr, l, x, sp.fmt, x0, x1);
                }
                foreach (var ld in l.leaders) draw_leader (cr, l, ld);
                foreach (var ar in l.build.anchors) {
                    if (ar.disp < l.disp_start || ar.disp >= l.disp_end || l.is_drop) continue;
                    var bb = ar.item.bounds ();
                    double left, top;
                    TextEngine.anchor_box (l, ar, out left, out top);
                    cr.save ();
                    cr.translate (left - bb.x, top - bb.y);
                    draw_item (cr, ar.item, false, -1);
                    cr.restore ();
                }
                if (opts.links && !l.is_drop) {
                    foreach (var sp in l.build.spans) {
                        if (sp.end <= l.disp_start || sp.start >= l.disp_end || sp.fmt.link == null || sp.fmt.link == "") continue;
                        string? attrs = link_attrs (sp.fmt.link);
                        if (attrs == null && opts.link_sink == null) continue;
                        double x0, x1;
                        span_range (l, sp, x, out x0, out x1);
                        if (x1 - x0 > 0.01) link_rect (cr, sp.fmt.link, attrs ?? "", x0, l.baseline - l.ascent, x1 - x0, l.ascent + l.descent);
                    }
                }
            }
        }

        private void draw_rule (Cairo.Context cr, LaidLine l, bool above) {
            string? spec = above ? l.build.pf.rule_above : l.build.pf.rule_below;
            if (spec == null || spec == "") return;
            string[] f = spec.split (";");
            double weight = Units.parse_num (f[0], 1);
            string color = f.length > 1 ? f[1] : ColorRef.BLACK;
            double offset = f.length > 2 ? Units.parse_num (f[2], 4) : 4;
            if (weight <= 0) return;
            double y = above ? l.baseline - l.ascent - offset : l.baseline + l.descent + offset;
            cr.save ();
            set_color (cr, color);
            cr.set_line_width (weight);
            cr.move_to (l.x, y);
            cr.line_to (l.x + l.width, y);
            cr.stroke ();
            cr.restore ();
        }

        private void draw_leader (Cairo.Context cr, LaidLine l, Leader ld) {
            var layout = new Pango.Layout (TextEngine.context ());
            layout.set_font_description (TextEngine.font_desc (ld.fmt));
            layout.set_text (ld.text, -1);
            int w, h;
            layout.get_size (out w, out h);
            double unit = w / (double) Pango.SCALE;
            if (unit <= 0.1) return;
            double avail = ld.x1 - ld.x0 - unit * 0.3;
            int n = (int) Math.floor (avail / unit);
            if (n <= 0) return;
            var sb = new StringBuilder ();
            for (int i = 0; i < n; i++) sb.append (ld.text);
            layout.set_text (sb.str, -1);
            set_color (cr, ld.fmt.color ?? ColorRef.BLACK);
            double x = l.x + l.x_off + ld.x1 - n * unit;
            cr.move_to (x, l.baseline);
            if (opts.glyph_sink == null || !opts.glyph_sink.line (cr, layout.get_line_readonly (0), x, l.baseline)) Pango.cairo_show_layout_line (cr, layout.get_line_readonly (0));
        }

        public void draw_table (Cairo.Context cr, TableItem t, int page_index) {
            draw_frame_box (cr, t);
            TableItem m;
            bool overset;
            var rows = TableFlow.rows_for (pub, t, out m, out overset);
            double tw = 0;
            foreach (var v in m.col_w) tw += v;
            double sx = t != m && tw > 0 ? t.w / tw : 1;
            var cw_list = new Gee.ArrayList<double?> ();
            foreach (var v in m.col_w) cw_list.add (v * sx);
            var row_y = new Gee.HashMap<int, double?> ();
            double y = 0;
            foreach (int r in rows) {
                row_y[r] = y;
                y += m.row_h[r];
            }
            double total_h = y;
            foreach (int r in rows) {
                double x = 0;
                double ry = row_y[r];
                string cell_tag = r < m.header_rows ? "TH" : "TD";
                if (opts.tagged) cr.tag_begin ("TR", "");
                for (int c = 0; c < m.cols; c++) {
                    var cell = m.cells[r][c];
                    if (!cell.covered) {
                        if (opts.tagged) cr.tag_begin (cell_tag, "");
                        double cw = 0, ch = 0;
                        for (int k = c; k < c + cell.col_span && k < m.cols; k++) cw += cw_list[k];
                        for (int k = r; k < r + cell.row_span && k < m.rows; k++) if (row_y.has_key (k)) ch += m.row_h[k];
                        string fill = cell.fill;
                        var cstyle = TableStyles.effective_cell (pub, m, r, c);
                        if (fill == ColorRef.NONE && cstyle != null && cstyle.fill != "") fill = cstyle.fill;
                        int valign = cell.valign != 0 || cstyle == null || cstyle.valign < 0 ? cell.valign : cstyle.valign;
                        int diagonal = cell.diagonal != 0 || cstyle == null || cstyle.diagonal < 0 ? cell.diagonal : cstyle.diagonal;
                        if (fill == ColorRef.NONE) {
                            if (r < m.header_rows && m.header_fill != ColorRef.NONE) fill = m.header_fill;
                            else if (r >= m.header_rows && (r - m.header_rows) % 2 == 1 && m.alt_fill != ColorRef.NONE) fill = m.alt_fill;
                        }
                        if (fill != ColorRef.NONE) {
                            set_color (cr, fill);
                            cr.rectangle (x, ry, cw, ch);
                            cr.fill ();
                        }
                        double inset = m.cell_inset;
                        var fr = cache.cell (cell.story, double.max (1, cw - 2 * inset), 100000, page_index);
                        double content = fr.content_height;
                        double dy = 0;
                        if (valign == 1) dy = (ch - 2 * inset - content) / 2;
                        else if (valign == 2) dy = ch - 2 * inset - content;
                        cr.save ();
                        cr.rectangle (x, ry, cw, ch);
                        cr.clip ();
                        cr.translate (x + inset, ry + inset + double.max (0, dy));
                        draw_lines (cr, fr.lines);
                        cr.restore ();
                        if (diagonal != 0 && m.border_width > 0 && m.border_color != ColorRef.NONE) {
                            cr.save ();
                            set_color (cr, m.border_color);
                            cr.set_line_width (m.border_width);
                            if (diagonal == 1) {
                                cr.move_to (x, ry);
                                cr.line_to (x + cw, ry + ch);
                            } else {
                                cr.move_to (x, ry + ch);
                                cr.line_to (x + cw, ry);
                            }
                            cr.stroke ();
                            cr.restore ();
                        }
                        if (!opts.print && opts.overset_marks && content > ch - 2 * inset + 0.5) {
                            cr.save ();
                            cr.translate (x, ry);
                            var dummy = new ShapeItem (ShapeKind.RECT);
                            dummy.w = cw;
                            dummy.h = ch;
                            draw_overset_mark (cr, dummy);
                            cr.restore ();
                        }
                        if (opts.tagged) cr.tag_end (cell_tag);
                    }
                    x += cw_list[c];
                }
                if (opts.tagged) cr.tag_end ("TR");
            }
            if (m.border_width > 0 && m.border_color != ColorRef.NONE) {
                set_color (cr, m.border_color);
                cr.set_line_width (m.border_width);
                foreach (int r in rows) {
                    double xx = 0;
                    for (int c = 0; c < m.cols; c++) {
                        var cell = m.cells[r][c];
                        if (!cell.covered) {
                            double cw = 0, ch = 0;
                            for (int k = c; k < c + cell.col_span && k < m.cols; k++) cw += cw_list[k];
                            for (int k = r; k < r + cell.row_span && k < m.rows; k++) if (row_y.has_key (k)) ch += m.row_h[k];
                            cr.rectangle (xx, row_y[r], cw, ch);
                        }
                        xx += cw_list[c];
                    }
                }
                cr.stroke ();
            }
            if (overset && !opts.print && opts.overset_marks && t.flows ()) {
                var dummy = new ShapeItem (ShapeKind.RECT);
                dummy.w = t.w;
                dummy.h = double.max (t.h, total_h);
                draw_overset_mark (cr, dummy);
            }
            draw_frame_stroke (cr, t);
        }
    }
}
