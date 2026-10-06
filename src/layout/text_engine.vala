namespace Singularity.Apps.Publish {

    public class Leader {
        public double x0;
        public double x1;
        public string text;
        public CharFormat fmt;

        public Leader (double x0, double x1, string text, CharFormat fmt) {
            this.x0 = x0;
            this.x1 = x1;
            this.text = text;
            this.fmt = fmt;
        }
    }

    public class LaidLine {
        public ParaBuild build;
        public int para;
        public int start;
        public int end;
        public double x;
        public double baseline;
        public double width;
        public double ascent;
        public double descent;
        public double x_off;
        public Pango.Layout layout;
        public int window;
        public int disp_start;
        public int disp_end;
        public int column;
        public bool is_drop = false;
        public bool para_first = false;
        public bool para_last = false;
        public double hscale = 1;
        public bool composed = false;
        public Gee.ArrayList<Leader> leaders = new Gee.ArrayList<Leader> ();

        public unowned Pango.LayoutLine line () {
            return layout.get_line_readonly (0);
        }

        public double caret_x (int story_offset) {
            if (is_drop) return x;
            int disp = build.disp_of (story_offset) - window;
            int xpos;
            line ().index_to_x (disp.clamp (0, layout.get_text ().length), false, out xpos);
            return x + x_off + xpos / (double) Pango.SCALE * hscale;
        }

        public int hit (double px) {
            int idx, trailing;
            line ().x_to_index ((int) ((px - x - x_off) / hscale * Pango.SCALE), out idx, out trailing);
            string t = layout.get_text ();
            int disp = idx;
            if (trailing > 0 && idx < t.length) {
                int j = idx;
                for (int k = 0; k < trailing && j < t.length; k++) {
                    unichar c = t.get_char (j);
                    j += c.to_utf8 (null);
                }
                disp = j;
            }
            int off = build.story_of (disp + window);
            return off.clamp (start, end);
        }
    }

    public class NoteBlock {
        public int column;
        public int line_index;
        public int number;
        public Story note;
        public FrameResult box;
        public double height;
        public double x;
        public double w;
        public double col_bottom;
        public double y;
        public bool continued = false;
    }

    public class FrameResult {
        public TextFrame? frame;
        public Gee.ArrayList<LaidLine> lines = new Gee.ArrayList<LaidLine> ();
        public Gee.ArrayList<NoteBlock> notes = new Gee.ArrayList<NoteBlock> ();
        public TextPos first;
        public TextPos last;
        public bool empty = true;
        public double content_height = 0;
        public int page_index = -1;

        public FrameResult (TextFrame? frame) {
            this.frame = frame;
        }
    }

    public class StoryResult {
        public Story story;
        public Gee.ArrayList<FrameResult> frames = new Gee.ArrayList<FrameResult> ();
        public bool overset = false;
        public TextPos overset_at;
        public int overset_chars = 0;
        public double scale = 1;

        public StoryResult (Story story) {
            this.story = story;
        }

        public FrameResult? frame_result (int frame_id) {
            foreach (var f in frames) if (f.frame != null && f.frame.id == frame_id) return f;
            return null;
        }
    }

    public class Band {
        public double a;
        public double b;

        public Band (double a, double b) {
            this.a = a;
            this.b = b;
        }
    }

    public class Obstacle {
        public Gee.ArrayList<Point?> poly = new Gee.ArrayList<Point?> ();
        public Gee.ArrayList<double?>? rows = null;
        public double row_y0 = 0;
        public double row_step = 1;
        public double offset;
        public WrapMode mode;
        public WrapSide side;

        public Gee.ArrayList<Band> intervals (double y0, double y1) {
            var result = new Gee.ArrayList<Band> ();
            double ya = y0 - offset, yb = y1 + offset;
            int n = poly.size;
            if (n < 3) return result;
            int samples = 5;
            for (int k = 0; k < samples; k++) {
                double yy = ya + (yb - ya) * k / (samples - 1);
                var xs = new Gee.ArrayList<double?> ();
                for (int i = 0; i < n; i++) {
                    var p = poly[i];
                    var q = poly[(i + 1) % n];
                    if ((p.y <= yy && q.y > yy) || (q.y <= yy && p.y > yy)) xs.add (p.x + (yy - p.y) / (q.y - p.y) * (q.x - p.x));
                }
                xs.sort ((a, b) => a < b ? -1 : (a > b ? 1 : 0));
                for (int i = 0; i + 1 < xs.size; i += 2) result.add (new Band (xs[i] - offset, xs[i + 1] + offset));
            }
            result.sort ((a, b) => a.a < b.a ? -1 : (a.a > b.a ? 1 : 0));
            var merged = new Gee.ArrayList<Band> ();
            foreach (var b in result) {
                if (merged.size > 0 && b.a <= merged[merged.size - 1].b) merged[merged.size - 1].b = double.max (merged[merged.size - 1].b, b.b);
                else merged.add (new Band (b.a, b.b));
            }
            return merged;
        }

        public bool extent (double y0, double y1, out double x0, out double x1) {
            x0 = double.MAX;
            x1 = -double.MAX;
            double ya = y0 - offset, yb = y1 + offset;
            if (rows != null && rows.size > 0) {
                for (int i = 0; i < rows.size / 2; i++) {
                    double ry = row_y0 + i * row_step;
                    if (ry + row_step < ya || ry > yb) continue;
                    double? l = rows[2 * i], r = rows[2 * i + 1];
                    if (l == null || r == null || l > r) continue;
                    x0 = double.min (x0, l);
                    x1 = double.max (x1, r);
                }
            } else {
                int n = poly.size;
                for (int i = 0; i < n; i++) {
                    var p = poly[i];
                    var q = poly[(i + 1) % n];
                    if (p.y >= ya && p.y <= yb) {
                        x0 = double.min (x0, p.x);
                        x1 = double.max (x1, p.x);
                    }
                    foreach (double yy in new double[] { ya, yb }) {
                        if ((p.y - yy) * (q.y - yy) < 0) {
                            double t = (yy - p.y) / (q.y - p.y);
                            double xx = p.x + t * (q.x - p.x);
                            x0 = double.min (x0, xx);
                            x1 = double.max (x1, xx);
                        }
                    }
                }
            }
            if (x0 > x1) return false;
            x0 -= offset;
            x1 += offset;
            return true;
        }
    }

    public delegate Gee.ArrayList<double?>? AlphaRowsFunc (ImageFrame frame, out double y0, out double step);

    public class TextEngine {
        public Publication pub;
        public int record = -1;
        public bool hyphenate = true;
        public double min_segment = 14;
        public double font_scale = 1;
        public unowned AlphaRowsFunc? alpha_rows = null;
        public unowned RunningLookup? running = null;
        public unowned XrefLookup? xref_lookup = null;
        private Gee.HashMap<int, Gee.ArrayList<Obstacle>>? anchor_obs = null;
        private Gee.HashMap<Story, int>? note_numbers = null;
        private Gee.HashMap<Story, int>? end_numbers = null;

        public void reset_notes () {
            note_numbers = null;
            end_numbers = null;
        }

        public Gee.HashMap<Story, int> endnote_map () {
            note_map ();
            return end_numbers;
        }

        public Gee.HashMap<Story, int> note_map () {
            if (note_numbers != null) return note_numbers;
            note_numbers = Footnotes.number_all (pub);
            end_numbers = Footnotes.number_endnotes (pub);
            if (pub.footnotes.restart == 1 && note_numbers.size > 0) {
                var pages = new Gee.HashMap<Story, int> ();
                foreach (var st in pub.stories.values) {
                    if (Footnotes.count (st) == 0 || pub.thread_frames (st.id).size == 0) continue;
                    var r = layout_story (st.id);
                    foreach (var fr in r.frames) foreach (var nb in fr.notes) pages[nb.note] = fr.page_index;
                }
                note_numbers = Footnotes.number_all (pub, pages);
            }
            return note_numbers;
        }
        private static Pango.Context? shared_context = null;

        public TextEngine (Publication pub) {
            this.pub = pub;
        }

        private static Pango.Context? rtl_context = null;

        public static Pango.Context context_rtl () {
            if (rtl_context == null) {
                var fm = Pango.CairoFontMap.new ();
                ((Pango.CairoFontMap) fm).set_resolution (72);
                rtl_context = fm.create_context ();
                var fo = new Cairo.FontOptions ();
                fo.set_hint_metrics (Cairo.HintMetrics.OFF);
                fo.set_hint_style (Cairo.HintStyle.NONE);
                fo.set_antialias (Cairo.Antialias.GRAY);
                Pango.cairo_context_set_font_options (rtl_context, fo);
                rtl_context.set_round_glyph_positions (false);
                rtl_context.set_base_dir (Pango.Direction.RTL);
            }
            return rtl_context;
        }

        private static Pango.Layout para_layout (ParaBuild b) {
            bool rtl = b.pf.direction == 1;
            var l = new Pango.Layout (rtl ? context_rtl () : context ());
            if (rtl) l.set_auto_dir (false);
            return l;
        }

        public static Pango.Context context () {
            if (shared_context == null) {
                var fm = Pango.CairoFontMap.new ();
                ((Pango.CairoFontMap) fm).set_resolution (72);
                shared_context = fm.create_context ();
                var fo = new Cairo.FontOptions ();
                fo.set_hint_metrics (Cairo.HintMetrics.OFF);
                fo.set_hint_style (Cairo.HintStyle.NONE);
                fo.set_antialias (Cairo.Antialias.GRAY);
                Pango.cairo_context_set_font_options (shared_context, fo);
                shared_context.set_round_glyph_positions (false);
            }
            return shared_context;
        }

        public static Pango.FontDescription font_desc (CharFormat f, double scale = 1) {
            var d = new Pango.FontDescription ();
            d.set_family (f.font ?? "Inter");
            d.set_absolute_size (double.max (1, f.size * scale) * Pango.SCALE);
            d.set_weight (f.bold == 1 ? Pango.Weight.BOLD : Pango.Weight.NORMAL);
            d.set_style (f.italic == 1 ? Pango.Style.ITALIC : Pango.Style.NORMAL);
            if (f.caps == 2) d.set_variant (Pango.Variant.SMALL_CAPS);
            if (f.variations != null && f.variations != "") d.set_variations (f.variations);
            return d;
        }

        private static uint16 c16 (double v) {
            return (uint16) Math.round (v.clamp (0, 1) * 65535);
        }

        public Pango.AttrList attrs_for (ParaBuild b, int from, int to) {
            var list = new Pango.AttrList ();
            foreach (var s in b.spans) {
                int a = int.max (s.start, from) - from;
                int e = int.min (s.end, to) - from;
                if (e <= a) continue;
                var f = s.fmt;
                bool pos = f.position == 1 || f.position == 2;
                double scale = pos ? 0.62 : 1;
                add (list, new Pango.AttrFontDesc (font_desc (f, scale)), a, e);
                var col = pub.resolve (f.color ?? ColorRef.BLACK);
                add (list, Pango.attr_foreground_new (c16 (col.r), c16 (col.g), c16 (col.b)), a, e);
                if (col.a < 0.999) add (list, Pango.attr_foreground_alpha_new (c16 (col.a)), a, e);
                if (f.underline == 1) add (list, Pango.attr_underline_new (Pango.Underline.SINGLE), a, e);
                if (f.strike == 1) add (list, Pango.attr_strikethrough_new (true), a, e);
                double track = f.tracking.is_nan () ? 0 : f.tracking;
                if (Math.fabs (track) > 0.01) add (list, Pango.attr_letter_spacing_new ((int) (f.size * track / 1000.0 * Pango.SCALE)), a, e);
                double rise = f.baseline_shift.is_nan () ? 0 : f.baseline_shift;
                if (f.position == 1) rise += f.size * 0.33;
                if (f.position == 2) rise -= f.size * 0.14;
                if (Math.fabs (rise) > 0.01) add (list, Pango.attr_rise_new ((int) (rise * Pango.SCALE)), a, e);
                var feats = new StringBuilder ();
                if (f.kerning == 0) feats.append ("kern 0");
                if (f.ligatures == 0) {
                    if (feats.len > 0) feats.append (", ");
                    feats.append ("liga 0, clig 0");
                }
                if (f.features != null && f.features != "") {
                    if (feats.len > 0) feats.append (", ");
                    feats.append (f.features);
                }
                if (feats.len > 0) add (list, new Pango.AttrFontFeatures (feats.str), a, e);
                if (f.caps == 1) add (list, Pango.attr_text_transform_new (Pango.TextTransform.UPPERCASE), a, e);
                if (f.lang != null && f.lang != "") add (list, new Pango.AttrLanguage (Pango.Language.from_string (f.lang)), a, e);
            }
            foreach (var ar in b.anchors) {
                if (ar.disp < from || ar.disp >= to) continue;
                var r = Pango.Rectangle ();
                if (ar.spec.inline ()) {
                    var bb = ar.item.bounds ();
                    r.x = 0;
                    r.width = (int) (bb.w * Pango.SCALE);
                    r.height = (int) (bb.h * Pango.SCALE);
                    r.y = (int) ((-bb.h + ar.spec.y_offset) * Pango.SCALE);
                } else {
                    r.x = 0;
                    r.y = 0;
                    r.width = 0;
                    r.height = 0;
                }
                add (list, Pango.AttrShape<int>.@new (r, r), ar.disp - from, ar.disp - from + 3);
            }
            return list;
        }

        private static void add (Pango.AttrList list, owned Pango.Attribute attr, int a, int e) {
            attr.start_index = a;
            attr.end_index = e;
            list.insert ((owned) attr);
        }

        public double leading_for (ParaBuild b, CharFormat? f = null) {
            if (b.pf.leading > 0.01) return b.pf.leading;
            return 1.2 * (f != null ? f.size : b.max_size);
        }

        private Pango.Layout make_layout (ParaBuild b, int from, int to, double width, bool last_allowed_justify, double tab_origin, double col_width) {
            var layout = para_layout (b);
            layout.set_text (b.text.substring (from, to - from), -1);
            layout.set_attributes (attrs_for (b, from, to));
            layout.set_width ((int) (double.max (1, width) * Pango.SCALE));
            layout.set_wrap (Pango.WrapMode.WORD_CHAR);
            var align = b.pf.text_align ();
            switch (align) {
                case TextAlign.CENTER: layout.set_alignment (Pango.Alignment.CENTER); break;
                case TextAlign.RIGHT: layout.set_alignment (Pango.Alignment.RIGHT); break;
                default: layout.set_alignment (b.pf.direction == 1 ? Pango.Alignment.RIGHT : Pango.Alignment.LEFT); break;
            }
            if (align == TextAlign.JUSTIFY || align == TextAlign.JUSTIFY_ALL) {
                layout.set_justify (true);
                if (align == TextAlign.JUSTIFY_ALL && last_allowed_justify) layout.set_justify_last_line (true);
            }
            layout.set_tabs (tab_array (b, tab_origin, col_width));
            return layout;
        }

        private Pango.TabArray tab_array (ParaBuild b, double origin, double col_width) {
            var stops = TabStop.parse (b.pf.tabs);
            var arr = new Pango.TabArray (0, false);
            int n = 0;
            if (b.has_prefix_tab) {
                double p = b.pf.left_indent - origin;
                if (p > 0.5) {
                    arr.resize (n + 1);
                    arr.set_tab (n++, Pango.TabAlign.LEFT, (int) (p * Pango.SCALE));
                }
            }
            double last = 0;
            foreach (var t in stops) {
                double p = t.pos - origin;
                if (p <= 0.5) continue;
                arr.resize (n + 1);
                Pango.TabAlign al = Pango.TabAlign.LEFT;
                switch (t.kind) {
                    case TabKind.RIGHT: al = Pango.TabAlign.RIGHT; break;
                    case TabKind.CENTER: al = Pango.TabAlign.CENTER; break;
                    case TabKind.DECIMAL:
                        al = Pango.TabAlign.DECIMAL;
                        arr.set_decimal_point (n, '.');
                        break;
                    default: break;
                }
                arr.set_tab (n++, al, (int) (p * Pango.SCALE));
                last = p;
            }
            double step = 36;
            double p2 = (Math.floor (last / step) + 1) * step;
            for (int i = 0; i < 40 && p2 < col_width + 400; i++) {
                arr.resize (n + 1);
                arr.set_tab (n++, Pango.TabAlign.LEFT, (int) (p2 * Pango.SCALE));
                p2 += step;
            }
            return arr;
        }

        private class ColumnBox {
            public double x;
            public double y;
            public double w;
            public double h;
        }

        private class FlowState {
            public int frame_i = 0;
            public int column = 0;
            public double baseline = double.NAN;
            public bool at_top = true;
            public Gee.ArrayList<NoteBlock> carry = new Gee.ArrayList<NoteBlock> ();
        }

        private Gee.ArrayList<ColumnBox> columns_of (TextFrame f) {
            var list = new Gee.ArrayList<ColumnBox> ();
            double ix = f.inset_left, iy = f.inset_top;
            double iw = f.w - f.inset_left - f.inset_right;
            double ih = f.h - f.inset_top - f.inset_bottom;
            if (f.vertical) {
                ix = f.inset_top;
                iy = f.inset_right;
                iw = f.h - f.inset_top - f.inset_bottom;
                ih = f.w - f.inset_left - f.inset_right;
            }
            if (f.auto_height) ih = 100000;
            int n = int.max (1, f.columns);
            double cw = (iw - f.gutter * (n - 1)) / n;
            for (int i = 0; i < n; i++) {
                var c = new ColumnBox ();
                c.x = ix + i * (cw + f.gutter);
                c.y = iy;
                c.w = double.max (1, cw);
                c.h = double.max (1, ih);
                list.add (c);
            }
            return list;
        }

        public int page_of_frame (TextFrame f) {
            var r = pub.find_item (f.id);
            if (r == null || r.page == null) return -1;
            return pub.pages.index_of (r.page);
        }

        public Gee.ArrayList<Obstacle> obstacles_for (TextFrame f, int page_index, bool on_master) {
            var list = new Gee.ArrayList<Obstacle> ();
            if (f.ignore_wrap || f.vertical) return list;
            var items = new Gee.ArrayList<Item> ();
            if (page_index >= 0 && page_index < pub.pages.size) {
                items.add_all (pub.master_items_for (page_index));
                items.add_all (pub.pages[page_index].items);
            } else {
                var r = pub.find_item (f.id);
                if (r != null && r.master != null) items.add_all (r.list);
            }
            foreach (var it in items) collect_obstacles (it, f, list);
            return list;
        }

        private void collect_obstacles (Item it, TextFrame f, Gee.ArrayList<Obstacle> list) {
            if (it.id == f.id || it.hidden) return;
            var layer = pub.layer (it.layer);
            if (layer != null && !layer.visible) return;
            var g = it as GroupItem;
            if (g != null && !g.wrap.wraps ()) {
                foreach (var c in g.children) collect_obstacles (c, f, list);
                return;
            }
            if (!it.wrap.wraps ()) return;
            var o = new Obstacle ();
            o.offset = it.wrap_offset;
            o.mode = it.wrap;
            o.side = it.wrap_side;
            Gee.ArrayList<Point?> pts;
            if (it.wrap_points.size >= 3 && it.wrap != WrapMode.JUMP) {
                pts = it.wrap_outline ();
            } else if (it.wrap == WrapMode.CONTOUR || it.wrap == WrapMode.THROUGH) {
                var im = it as ImageFrame;
                if (im != null && alpha_rows != null && im.rotation == 0 && f.rotation == 0 && it.wrap == WrapMode.CONTOUR) {
                    double y0, step;
                    var rows = alpha_rows (im, out y0, out step);
                    if (rows != null) {
                        o.rows = new Gee.ArrayList<double?> ();
                        foreach (var v in rows) {
                            if (v == null) o.rows.add (null);
                            else o.rows.add (v - f.x);
                        }
                        o.row_y0 = y0 - f.y;
                        o.row_step = step;
                    }
                }
                pts = it.outline ();
            } else {
                pts = new Gee.ArrayList<Point?> ();
                pts.add (it.to_page (0, 0));
                pts.add (it.to_page (it.w, 0));
                pts.add (it.to_page (it.w, it.h));
                pts.add (it.to_page (0, it.h));
            }
            foreach (var p in pts) o.poly.add (f.to_local (p.x, p.y));
            list.add (o);
        }

        private Gee.ArrayList<Band> free_bands (ColumnBox col, double y0, double y1, Gee.ArrayList<Obstacle> obstacles, double left_extra, double right_extra, double font_size = 0) {
            var bands = new Gee.ArrayList<Band> ();
            bands.add (new Band (col.x + left_extra, col.x + col.w - right_extra));
            foreach (var o in obstacles) {
                double ox0, ox1;
                if (o.mode == WrapMode.JUMP) {
                    double jx0, jx1;
                    if (o.extent (y0, y1, out jx0, out jx1) && jx1 > col.x && jx0 < col.x + col.w) bands.clear ();
                    continue;
                }
                if (o.mode == WrapMode.THROUGH && o.rows == null) {
                    var cuts = o.intervals (y0, y1);
                    var kept = new Gee.ArrayList<Band> ();
                    foreach (var b in bands) {
                        var parts = new Gee.ArrayList<Band> ();
                        parts.add (b);
                        foreach (var cut in cuts) {
                            var np = new Gee.ArrayList<Band> ();
                            foreach (var pb in parts) {
                                if (cut.b <= pb.a || cut.a >= pb.b) {
                                    np.add (pb);
                                    continue;
                                }
                                if (cut.a > pb.a) np.add (new Band (pb.a, cut.a));
                                if (cut.b < pb.b) np.add (new Band (cut.b, pb.b));
                            }
                            parts = np;
                        }
                        kept.add_all (parts);
                    }
                    bands = kept;
                    continue;
                }
                if (!o.extent (y0, y1, out ox0, out ox1)) continue;
                if (ox1 <= col.x || ox0 >= col.x + col.w) continue;
                switch (o.side) {
                    case WrapSide.LEFT:
                        ox1 = col.x + col.w + 1;
                        break;
                    case WrapSide.RIGHT:
                        ox0 = col.x - 1;
                        break;
                    case WrapSide.LARGEST:
                        double lw = ox0 - col.x, rw = col.x + col.w - ox1;
                        if (lw >= rw) ox1 = col.x + col.w + 1;
                        else ox0 = col.x - 1;
                        break;
                    default:
                        break;
                }
                var next = new Gee.ArrayList<Band> ();
                foreach (var b in bands) {
                    if (ox1 <= b.a || ox0 >= b.b) {
                        next.add (b);
                        continue;
                    }
                    if (ox0 > b.a) next.add (new Band (b.a, ox0));
                    if (ox1 < b.b) next.add (new Band (ox1, b.b));
                }
                bands = next;
            }
            var result = new Gee.ArrayList<Band> ();
            double min_w = obstacles.size > 0 ? double.max (min_segment, font_size * 3.5) : min_segment;
            foreach (var b in bands) if (b.b - b.a >= min_w) result.add (b);
            return result;
        }

        private double snap_grid (TextFrame f, double baseline) {
            if (f.vertical) return baseline;
            if (f.own_grid) {
                if (f.grid_step < 1) return baseline;
                double kk = Math.ceil ((baseline - f.grid_start) / f.grid_step - 1e-6);
                if (kk < 0) kk = 0;
                return f.grid_start + kk * f.grid_step;
            }
            if (f.rotation != 0) return baseline;
            double step = pub.settings.baseline_step;
            if (step < 1) return baseline;
            double page_y = f.y + baseline;
            double start = pub.settings.baseline_start;
            double k = Math.ceil ((page_y - start) / step - 1e-6);
            if (k < 0) k = 0;
            return start + k * step - f.y;
        }

        public StoryResult layout_story (int story_id, int page_override = -2, TextFrame? only = null) {
            var story = pub.story (story_id);
            var frames = new Gee.ArrayList<TextFrame> ();
            if (only != null) frames.add (only);
            else frames = pub.thread_frames (story_id);
            var pages = new Gee.ArrayList<int> ();
            var masters = new Gee.ArrayList<bool> ();
            foreach (var f in frames) {
                if (page_override != -2) {
                    pages.add (page_override);
                    masters.add (true);
                } else {
                    var r = pub.find_item (f.id);
                    pages.add (r != null && r.page != null ? pub.pages.index_of (r.page) : -1);
                    masters.add (r != null && r.master != null);
                }
            }
            if (frames.size > 0 && frames[0].autofit != 0 && !frames[frames.size - 1].auto_height && !story.is_empty ()) return autofit (story, frames, pages, masters, frames[0].autofit);
            return flow (story, frames, pages, masters);
        }

        private bool fits (StoryResult r, Gee.ArrayList<TextFrame> frames) {
            if (r.overset) return false;
            foreach (var fr in r.frames) {
                if (fr.frame == null) continue;
                var f = fr.frame;
                double limit = f.h - f.inset_bottom + 0.5;
                foreach (var l in fr.lines) if (l.baseline + l.descent > limit) return false;
                double right = f.w - f.inset_right + 0.5;
                foreach (var l in fr.lines) {
                    if (l.is_drop) continue;
                    Pango.Rectangle ink, logical;
                    l.line ().get_extents (out ink, out logical);
                    if (l.x + l.x_off + logical.width / (double) Pango.SCALE > right + 1 && l.end - l.start <= 1) return false;
                }
            }
            return true;
        }

        public StoryResult autofit (Story story, Gee.ArrayList<TextFrame> frames, Gee.ArrayList<int> pages, Gee.ArrayList<bool> masters, int mode) {
            double saved = font_scale;
            font_scale = 1;
            var at_one = flow (story, frames, pages, masters);
            if (mode == 1 && fits (at_one, frames)) {
                font_scale = saved;
                return at_one;
            }
            double lo = 0.05, hi = mode == 1 ? 1.0 : 24.0;
            StoryResult? best = null;
            double best_s = lo;
            if (mode == 2 && fits (at_one, frames)) {
                lo = 1;
                best = at_one;
                best_s = 1;
            } else if (mode == 2) {
                hi = 1;
            }
            for (int i = 0; i < 14 && hi - lo > 0.004; i++) {
                double mid = (lo + hi) / 2;
                font_scale = mid;
                var r = flow (story, frames, pages, masters);
                if (fits (r, frames)) {
                    lo = mid;
                    best = r;
                    best_s = mid;
                } else {
                    hi = mid;
                }
            }
            if (best == null) {
                font_scale = lo;
                best = flow (story, frames, pages, masters);
                best_s = lo;
            }
            best.scale = best_s;
            font_scale = saved;
            return best;
        }

        public FrameResult layout_box (Story story, double w, double h, int page_index = -1) {
            var f = new TextFrame ();
            f.w = w;
            f.h = h;
            f.ignore_wrap = true;
            var frames = new Gee.ArrayList<TextFrame> ();
            frames.add (f);
            var pages = new Gee.ArrayList<int> ();
            pages.add (page_index);
            var masters = new Gee.ArrayList<bool> ();
            masters.add (false);
            var res = flow (story, frames, pages, masters, false);
            var fr = res.frames[0];
            fr.frame = null;
            return fr;
        }

        public StoryResult flow (Story story, Gee.ArrayList<TextFrame> frames, Gee.ArrayList<int> pages, Gee.ArrayList<bool> masters, bool use_obstacles = true) {
            var res = flow_once (story, frames, pages, masters, use_obstacles);
            if (!use_obstacles) return res;
            var placed = anchor_obstacles (res);
            if (placed.size == 0) return res;
            for (int pass = 0; pass < 3; pass++) {
                anchor_obs = placed;
                res = flow_once (story, frames, pages, masters, use_obstacles);
                anchor_obs = null;
                var again = anchor_obstacles (res);
                bool same = again.size == placed.size;
                if (same) {
                    foreach (var k in again.keys) {
                        if (!placed.has_key (k) || !same_obstacles (placed[k], again[k])) {
                            same = false;
                            break;
                        }
                    }
                }
                if (same) break;
                placed = again;
            }
            return res;
        }

        public static void anchor_box (LaidLine l, AnchorRef ar, out double left, out double top) {
            int xp;
            l.line ().index_to_x (ar.disp - l.window, false, out xp);
            double cx = l.x + l.x_off + xp / (double) Pango.SCALE * l.hscale;
            var bb = ar.item.bounds ();
            if (ar.spec.inline ()) {
                left = cx;
                top = l.baseline - bb.h + ar.spec.y_offset;
            } else {
                left = (ar.spec.x_ref == 1 ? 0 : cx) + ar.spec.x_offset;
                top = l.baseline + ar.spec.y_offset;
            }
        }

        private Gee.HashMap<int, Gee.ArrayList<Obstacle>> anchor_obstacles (StoryResult res) {
            var map = new Gee.HashMap<int, Gee.ArrayList<Obstacle>> ();
            for (int i = 0; i < res.frames.size; i++) {
                foreach (var l in res.frames[i].lines) {
                    if (l.is_drop) continue;
                    foreach (var ar in l.build.anchors) {
                        if (ar.disp < l.disp_start || ar.disp >= l.disp_end || ar.spec.inline () || !ar.item.wrap.wraps ()) continue;
                        double left, top;
                        anchor_box (l, ar, out left, out top);
                        var bb = ar.item.bounds ();
                        var o = new Obstacle ();
                        o.offset = ar.item.wrap_offset;
                        o.mode = ar.item.wrap == WrapMode.CONTOUR ? WrapMode.BOUNDING_BOX : ar.item.wrap;
                        o.side = ar.item.wrap_side;
                        o.poly.add (Point (left, top));
                        o.poly.add (Point (left + bb.w, top));
                        o.poly.add (Point (left + bb.w, top + bb.h));
                        o.poly.add (Point (left, top + bb.h));
                        if (!map.has_key (i)) map[i] = new Gee.ArrayList<Obstacle> ();
                        map[i].add (o);
                    }
                }
            }
            return map;
        }

        private static bool same_obstacles (Gee.ArrayList<Obstacle> a, Gee.ArrayList<Obstacle> b) {
            if (a.size != b.size) return false;
            for (int i = 0; i < a.size; i++) {
                for (int k = 0; k < 4; k++) {
                    if (Math.fabs (a[i].poly[k].x - b[i].poly[k].x) > 0.5 || Math.fabs (a[i].poly[k].y - b[i].poly[k].y) > 0.5) return false;
                }
            }
            return true;
        }

        private StoryResult flow_once (Story story, Gee.ArrayList<TextFrame> frames, Gee.ArrayList<int> pages, Gee.ArrayList<bool> masters, bool use_obstacles) {
            var res = new StoryResult (story);
            foreach (var f in frames) res.frames.add (new FrameResult (f));
            for (int i = 0; i < frames.size; i++) res.frames[i].page_index = pages[i];
            if (frames.size == 0) {
                res.overset = !story.is_empty ();
                res.overset_at = TextPos (0, 0);
                res.overset_chars = story.char_count ();
                return res;
            }
            var col_cache = new Gee.HashMap<int, Gee.ArrayList<ColumnBox>> ();
            var obs_cache = new Gee.HashMap<int, Gee.ArrayList<Obstacle>> ();
            var st = new FlowState ();
            var counter = new ListCounter ();
            var fc = new FieldContext (pub);
            fc.record = record;
            fc.running = running;
            fc.note_numbers = note_map ();
            fc.xref = xref_lookup;
            fc.endnote_numbers = end_numbers;
            bool done = true;
            int pi = 0;

            int keep_guard = 0;
            while (pi < story.paras.size) {
                if (st.frame_i >= frames.size) {
                    done = false;
                    break;
                }
                var para = story.paras[pi];
                fc.page_index = pages[st.frame_i];
                fc.prev_page = st.frame_i > 0 ? pages[st.frame_i - 1] : -1;
                fc.next_page = st.frame_i + 1 < frames.size ? pages[st.frame_i + 1] : -1;
                var saved_counter = new ListCounter ();
                for (int k = 0; k < 9; k++) saved_counter.counts[k] = counter.counts[k];
                saved_counter.active = counter.active;
                var b = ParaBuild.build (pub, para, pi, fc, counter, hyphenate, font_scale);
                var start_state = new FlowState ();
                start_state.frame_i = st.frame_i;
                start_state.column = st.column;
                start_state.baseline = st.baseline;
                start_state.at_top = st.at_top;
                var start_counts = new int[res.frames.size];
                for (int k = 0; k < res.frames.size; k++) start_counts[k] = res.frames[k].lines.size;
                bool complete = flow_paragraph (b, frames, pages, masters, st, res, col_cache, obs_cache, use_obstacles);
                if (!complete) {
                    done = false;
                    break;
                }
                bool moved = st.frame_i != start_state.frame_i || st.column != start_state.column;
                bool keep = (b.pf.keep_lines == 1 && moved) || (b.pf.keep_next == 1 && pi + 1 < story.paras.size && next_moves (story, pi, st, frames, pages, masters, res, col_cache, obs_cache, use_obstacles, fc, counter));
                if (keep && !start_state.at_top && keep_guard < 200) {
                    keep_guard++;
                    for (int k = 0; k < res.frames.size; k++) {
                        while (res.frames[k].lines.size > start_counts[k]) res.frames[k].lines.remove_at (res.frames[k].lines.size - 1);
                        var gone = new Gee.ArrayList<NoteBlock> ();
                        foreach (var nb in res.frames[k].notes) if (nb.line_index >= start_counts[k]) gone.add (nb);
                        res.frames[k].notes.remove_all (gone);
                    }
                    st.frame_i = start_state.frame_i;
                    st.column = start_state.column;
                    advance_column (st, frames, col_cache);
                    for (int k = 0; k < 9; k++) counter.counts[k] = saved_counter.counts[k];
                    counter.active = saved_counter.active;
                    continue;
                }
                pi++;
            }
            if (!done) {
                var pos = TextPos (0, 0);
                bool any = false;
                foreach (var fr in res.frames) foreach (var l in fr.lines) {
                    if (l.is_drop) continue;
                    var e = TextPos (l.para, l.end);
                    if (!any || e.compare (pos) > 0) pos = e;
                    any = true;
                }
                if (any && pos.offset >= story.paras[pos.para].length () && pos.para + 1 < story.paras.size) pos = TextPos (pos.para + 1, 0);
                if (!any) pos = TextPos (0, 0);
                res.overset_at = pos;
                res.overset_chars = story.char_count () - story.linear (pos);
                res.overset = res.overset_chars > 0 || (any == false && story.paras.size > 0);
                if (!any && story.is_empty ()) res.overset = false;
            }
            foreach (var fr in res.frames) finish_frame (fr, col_cache);
            return res;
        }

        private bool next_moves (Story story, int pi, FlowState st, Gee.ArrayList<TextFrame> frames, Gee.ArrayList<int> pages, Gee.ArrayList<bool> masters, StoryResult res, Gee.HashMap<int, Gee.ArrayList<ColumnBox>> col_cache, Gee.HashMap<int, Gee.ArrayList<Obstacle>> obs_cache, bool use_obstacles, FieldContext fc, ListCounter counter) {
            var probe = new FlowState ();
            probe.frame_i = st.frame_i;
            probe.column = st.column;
            probe.baseline = st.baseline;
            probe.at_top = st.at_top;
            var c2 = new ListCounter ();
            for (int k = 0; k < 9; k++) c2.counts[k] = counter.counts[k];
            c2.active = counter.active;
            var b = ParaBuild.build (pub, story.paras[pi + 1], pi + 1, fc, c2, hyphenate, font_scale);
            var tmp = new StoryResult (story);
            foreach (var f in res.frames) tmp.frames.add (new FrameResult (f.frame));
            var line = first_line_probe (b, frames, pages, masters, probe, tmp, col_cache, obs_cache, use_obstacles);
            return line && (probe.frame_i != st.frame_i || probe.column != st.column);
        }

        private bool first_line_probe (ParaBuild b, Gee.ArrayList<TextFrame> frames, Gee.ArrayList<int> pages, Gee.ArrayList<bool> masters, FlowState st, StoryResult res, Gee.HashMap<int, Gee.ArrayList<ColumnBox>> col_cache, Gee.HashMap<int, Gee.ArrayList<Obstacle>> obs_cache, bool use_obstacles) {
            return flow_paragraph (b, frames, pages, masters, st, res, col_cache, obs_cache, use_obstacles, 1);
        }

        private Gee.ArrayList<ColumnBox> cols (TextFrame f, int i, Gee.HashMap<int, Gee.ArrayList<ColumnBox>> cache) {
            if (!cache.has_key (i)) cache[i] = columns_of (f);
            return cache[i];
        }

        private void advance_column (FlowState st, Gee.ArrayList<TextFrame> frames, Gee.HashMap<int, Gee.ArrayList<ColumnBox>> cache) {
            st.column++;
            if (st.frame_i < frames.size && st.column >= cols (frames[st.frame_i], st.frame_i, cache).size) {
                st.column = 0;
                st.frame_i++;
            }
            st.baseline = double.NAN;
            st.at_top = true;
        }

        private bool flow_paragraph (ParaBuild b, Gee.ArrayList<TextFrame> frames, Gee.ArrayList<int> pages, Gee.ArrayList<bool> masters, FlowState st, StoryResult res, Gee.HashMap<int, Gee.ArrayList<ColumnBox>> col_cache, Gee.HashMap<int, Gee.ArrayList<Obstacle>> obs_cache, bool use_obstacles, int max_lines = -1) {
            var pf = b.pf;
            int total = b.text.length;
            int cur = 0;
            bool first = true;
            int lines_done = 0;
            double drop_w = 0;
            LaidLine? drop = null;
            int drop_lines = pf.drop_lines >= 2 && b.drop_bytes > 0 ? pf.drop_lines : 0;
            double base_lead = leading_for (b);
            Gee.ArrayList<ComposedLine>? plan = null;
            int plan_i = 0;
            double plan_w = -1;
            bool use_composer = pf.composer == 0 && drop_lines == 0;
            if (drop_lines > 0) {
                drop = make_drop (b, drop_lines, base_lead, out drop_w);
                cur = b.prefix_bytes + b.drop_bytes;
            }
            while (true) {
                if (max_lines >= 0 && lines_done >= max_lines) return true;
                if (st.frame_i >= frames.size) return false;
                var frame = frames[st.frame_i];
                var columns = cols (frame, st.frame_i, col_cache);
                if (st.column >= columns.size) {
                    advance_column (st, frames, col_cache);
                    continue;
                }
                var col = columns[st.column];
                var fr = res.frames[st.frame_i];
                if (pub.output != null) pub.output.overprint = frame.overprint_fill;
                Gee.ArrayList<Obstacle> obstacles;
                if (!use_obstacles) obstacles = new Gee.ArrayList<Obstacle> ();
                else {
                    if (!obs_cache.has_key (st.frame_i)) {
                        var found = obstacles_for (frame, pages[st.frame_i], masters[st.frame_i]);
                        if (anchor_obs != null && anchor_obs.has_key (st.frame_i)) found.add_all (anchor_obs[st.frame_i]);
                        obs_cache[st.frame_i] = found;
                    }
                    obstacles = obs_cache[st.frame_i];
                }
                if (st.carry.size > 0 && !has_notes (fr, st.column)) {
                    foreach (var nb in st.carry) {
                        nb.column = st.column;
                        nb.x = col.x;
                        nb.w = col.w;
                        nb.col_bottom = col.y + col.h;
                        nb.line_index = fr.lines.size - 1;
                        fr.notes.add (nb);
                    }
                    st.carry.clear ();
                }
                double bottom = col.y + col.h - reserved (fr, st.column);
                bool auto_lead = pf.leading <= 0.01;
                double lead = auto_lead ? 1.2 * b.max_size : pf.leading;
                double asc = auto_lead ? b.max_size * 0.95 : lead * 0.8;
                double desc = auto_lead ? b.max_size * 0.25 : lead * 0.2;
                bool top = st.baseline.is_nan ();
                double baseline = top ? col.y + asc : st.baseline + lead + (first && !st.at_top ? pf.space_before : 0);
                if (pf.align_grid == 1 && (frame.rotation == 0 || frame.own_grid)) baseline = snap_grid (frame, baseline);
                if (baseline + desc > bottom + 0.01) {
                    advance_column (st, frames, col_cache);
                    continue;
                }
                double li = pf.left_indent + (first ? pf.first_indent : 0);
                double ri = pf.right_indent;
                if (drop != null && lines_done < drop_lines) li = double.max (li, pf.left_indent) + drop_w;
                var bands = free_bands (col, baseline - asc, baseline + desc, obstacles, double.max (0, li), double.max (0, ri), b.base_cf.size);
                if (bands.size == 0) {
                    double step = double.max (2, lead / 3);
                    st.baseline = (top ? col.y + asc : baseline) - lead + step;
                    st.at_top = false;
                    if (st.baseline + lead + desc > col.y + col.h) advance_column (st, frames, col_cache);
                    continue;
                }
                int start_cur = cur;
                bool finished = false;
                double line_asc = 0, line_desc = 0;
                var placed = new Gee.ArrayList<LaidLine> ();
                foreach (var band in bands) {
                    LaidLine? ll;
                    if (start_cur >= total) {
                        if (placed.size > 0) break;
                        ll = empty_line (b, start_cur, band);
                    } else {
                        ll = null;
                        double bw = band.b - band.a;
                        if (use_composer && bands.size == 1) {
                            if (plan == null || plan_i >= plan.size || plan[plan_i].start != start_cur || Math.fabs (plan_w - bw) > 0.5) {
                                plan = compose_from (b, start_cur, bw, bw + (first ? pf.first_indent : 0));
                                plan_i = 0;
                                plan_w = bw;
                                if (plan == null) use_composer = false;
                            }
                            if (plan != null && plan_i < plan.size && plan[plan_i].start == start_cur) {
                                ll = place_composed (b, plan[plan_i], band, col, plan_i == plan.size - 1);
                                plan_i++;
                                if (plan_i < plan.size) plan_w = bw + (first ? pf.first_indent : 0);
                            }
                        }
                        if (ll == null) ll = place_line (b, start_cur, total, band, col);
                    }
                    if (ll == null) continue;
                    ll.column = st.column;
                    ll.para_first = first && placed.size == 0;
                    placed.add (ll);
                    start_cur = ll.disp_end;
                    line_asc = double.max (line_asc, ll.ascent);
                    line_desc = double.max (line_desc, ll.descent);
                    if (start_cur >= total) {
                        finished = true;
                        break;
                    }
                }
                if (placed.size == 0) {
                    st.baseline = baseline;
                    st.at_top = false;
                    continue;
                }
                if (top) {
                    baseline = col.y + line_asc;
                    if (pf.align_grid == 1 && (frame.rotation == 0 || frame.own_grid)) baseline = snap_grid (frame, baseline);
                } else if (auto_lead) {
                    baseline = st.baseline + 1.2 * double.max (b.max_size, line_asc / 0.95) + (first && !st.at_top ? pf.space_before : 0);
                    if (pf.align_grid == 1 && (frame.rotation == 0 || frame.own_grid)) baseline = snap_grid (frame, baseline);
                }
                var fresh_notes = new Gee.ArrayList<NoteBlock> ();
                if (b.notes.size > 0) {
                    foreach (var ll in placed) {
                        foreach (var nr in b.notes) {
                            if (nr.disp < ll.disp_start || nr.disp >= ll.disp_end) continue;
                            fresh_notes.add (note_block (nr, col, st.column));
                        }
                    }
                }
                double needed = 0;
                if (fresh_notes.size > 0) {
                    bool had = has_notes (fr, st.column);
                    foreach (var nb in fresh_notes) {
                        needed += nb.height + (had ? pub.footnotes.space_between : pub.footnotes.space_before);
                        had = true;
                    }
                }
                bool column_empty = true;
                foreach (var l in fr.lines) if (l.column == st.column) column_empty = false;
                if (baseline + line_desc > bottom - needed + 0.5 && !(top && column_empty)) {
                    NoteBlock? rest = null;
                    if (pub.footnotes.split && fresh_notes.size > 0) {
                        var last_nb = fresh_notes[fresh_notes.size - 1];
                        double room = bottom - (baseline + line_desc) - (needed - last_nb.height);
                        rest = split_note (last_nb, room);
                    }
                    if (rest == null) {
                        advance_column (st, frames, col_cache);
                        continue;
                    }
                    st.carry.add (rest);
                }
                if (baseline + line_desc > col.y + col.h + 0.5 && !(top && fr.lines.size == 0 && line_desc + line_asc > col.h)) {
                    advance_column (st, frames, col_cache);
                    continue;
                }
                if (top && fr.lines.size == 0 && baseline + line_desc > col.y + col.h + 0.5) {
                    advance_column (st, frames, col_cache);
                    continue;
                }
                foreach (var ll in placed) {
                    ll.baseline = baseline;
                    fr.lines.add (ll);
                }
                foreach (var nb in fresh_notes) {
                    nb.line_index = fr.lines.size - 1;
                    fr.notes.add (nb);
                }
                if (drop != null && lines_done == 0) {
                    drop.x = col.x + double.max (0, pf.left_indent);
                    drop.column = st.column;
                    drop.baseline = baseline + (drop_lines - 1) * lead;
                    fr.lines.add (drop);
                }
                lines_done++;
                st.baseline = baseline;
                st.at_top = false;
                cur = start_cur;
                first = false;
                if (finished) {
                    placed[placed.size - 1].para_last = true;
                    if (drop != null && lines_done < drop_lines) st.baseline = drop.baseline;
                    st.baseline += pf.space_after;
                    return true;
                }
            }
        }

        private Pango.Layout full_layout (ParaBuild b) {
            var layout = para_layout (b);
            layout.set_text (b.text, -1);
            layout.set_attributes (attrs_for (b, 0, b.text.length));
            layout.set_width (-1);
            layout.set_font_description (font_desc (b.base_cf));
            return layout;
        }

        private Gee.ArrayList<ComposedLine>? compose_from (ParaBuild b, int from, double w0, double w_rest) {
            var full = full_layout (b);
            var comp = new ParagraphComposer (b.pf);
            if (!comp.prepare (full, from)) return null;
            var align = b.pf.text_align ();
            bool justify = align == TextAlign.JUSTIFY || align == TextAlign.JUSTIFY_ALL;
            return comp.compose ((line) => line == 0 ? w0 : w_rest, justify, align == TextAlign.JUSTIFY_ALL);
        }

        public static double optical_factor (unichar c) {
            switch (c) {
                case '"':
                case '\'':
                case 0x201C:
                case 0x201D:
                case 0x2018:
                case 0x2019:
                case 0x201E:
                case 0x201A:
                case '.':
                case ',':
                    return 1.0;
                case '-':
                case 0x2010:
                case 0x00AD:
                    return 0.75;
                case 0x2013:
                case ':':
                case ';':
                case 0x00AB:
                case 0x00BB:
                case 0x2039:
                case 0x203A:
                    return 0.5;
                case 0x2014:
                    return 0.25;
                case 'A':
                case 'V':
                case 'W':
                case 'Y':
                case 'T':
                case 'v':
                case 'w':
                case 'y':
                    return 0.12;
                case 'O':
                case 'C':
                case 'G':
                case 'Q':
                case 'o':
                case 'c':
                case 'e':
                    return 0.04;
                default:
                    return 0;
            }
        }

        private void optical_hangs (string text, Pango.LayoutLine line, out double left, out double right) {
            left = 0;
            right = 0;
            int i = 0;
            unichar c;
            if (text.get_next_char (ref i, out c)) {
                double f = optical_factor (c);
                if (f > 0) {
                    int x0, x1;
                    line.index_to_x (0, false, out x0);
                    line.index_to_x (i, false, out x1);
                    left = f * (x1 - x0).abs () / (double) Pango.SCALE;
                }
            }
            int end = text.length;
            while (end > 0 && (text[end - 1] == ' ' || text[end - 1] == '\t')) end--;
            if (end <= 0) return;
            int start = end;
            unichar last = 0;
            int k = 0;
            while (k < end) {
                start = k;
                if (!text.get_next_char (ref k, out last)) break;
            }
            double rf = optical_factor (last);
            if (rf > 0) {
                int x0, x1;
                line.index_to_x (start, false, out x0);
                line.index_to_x (end, false, out x1);
                right = rf * (x1 - x0).abs () / (double) Pango.SCALE;
            }
        }

        private LaidLine place_composed (ParaBuild b, ComposedLine cl, Band band, ColumnBox col, bool last) {
            double width = band.b - band.a;
            var pf = b.pf;
            string body = b.text.substring (cl.start, cl.end - cl.start);
            string text = cl.hyphen ? body + "\u2010" : body;
            var base_attrs = attrs_for (b, cl.start, cl.end);
            var attrs = new Pango.AttrList ();
            int body_len = body.length;
            foreach (unowned Pango.Attribute at in base_attrs.get_attributes ()) {
                var copy = at.copy ();
                if (copy.end_index >= body_len) copy.end_index = text.length;
                attrs.insert ((owned) copy);
            }
            var layout = para_layout (b);
            layout.set_text (text, -1);
            layout.set_attributes (attrs);
            layout.set_width (-1);
            layout.set_tabs (tab_array (b, band.a - col.x, col.w));
            unowned Pango.LayoutLine line = layout.get_line_readonly (0);
            Pango.Rectangle ink, logical;
            line.get_extents (out ink, out logical);
            double natural = logical.width / (double) Pango.SCALE;
            var align = pf.text_align ();
            bool justify_line = (align == TextAlign.JUSTIFY && !last) || align == TextAlign.JUSTIFY_ALL;
            double hang_l = 0, hang_r = 0;
            if (pf.optical == 1) {
                optical_hangs (cl.hyphen ? text : body, line, out hang_l, out hang_r);
                width += hang_l + hang_r;
            }
            int spaces = 0, glyphs = 0;
            unichar c;
            int i = 0;
            while (body.get_next_char (ref i, out c)) {
                if (c == ' ') spaces++;
                if (c != 0x00AD) glyphs++;
            }
            glyphs = int.max (0, glyphs - 1);
            double space_w = b.base_cf.size * 0.25;
            int sx0, sx1;
            int sp = body.index_of_char (' ');
            if (sp >= 0) {
                line.index_to_x (sp, false, out sx0);
                line.index_to_x (sp + 1, false, out sx1);
                if (sx1 > sx0) space_w = (sx1 - sx0) / (double) Pango.SCALE;
            }
            double wo = pf.word_opt.is_nan () ? 100 : pf.word_opt, wmin = pf.word_min.is_nan () ? 80 : pf.word_min, wmax = pf.word_max.is_nan () ? 133 : pf.word_max;
            double lo = pf.letter_opt.is_nan () ? 0 : pf.letter_opt, lmin = pf.letter_min.is_nan () ? 0 : pf.letter_min, lmax = pf.letter_max.is_nan () ? 0 : pf.letter_max;
            double go = pf.glyph_opt.is_nan () ? 100 : pf.glyph_opt, gmin = pf.glyph_min.is_nan () ? 100 : pf.glyph_min, gmax = pf.glyph_max.is_nan () ? 100 : pf.glyph_max;
            double space_extra = space_w * (wo - 100) / 100;
            double letter_extra = space_w * lo / 100;
            double hscale = go / 100;
            double body_w = natural - spaces * space_w;
            double cur_w = (body_w + glyphs * letter_extra) * hscale + spaces * (space_w + space_extra);
            if (justify_line) {
                double delta = width - cur_w;
                if (spaces > 0) {
                    double lo_s = space_w * (wmin - wo) / 100, hi_s = space_w * (wmax - wo) / 100;
                    double per = (delta / spaces).clamp (lo_s, hi_s);
                    space_extra += per;
                    delta -= per * spaces;
                }
                if (glyphs > 0 && Math.fabs (delta) > 0.01) {
                    double lo_l = space_w * (lmin - lo) / 100, hi_l = space_w * (lmax - lo) / 100;
                    double per = (delta / (glyphs * hscale)).clamp (lo_l, hi_l);
                    letter_extra += per;
                    delta -= per * glyphs * hscale;
                }
                double scaled_body = body_w + glyphs * letter_extra;
                if (scaled_body > 0 && Math.fabs (delta) > 0.01) {
                    double target = (hscale * scaled_body + delta) / scaled_body;
                    double ns = target.clamp (gmin / 100, gmax / 100);
                    delta -= (ns - hscale) * scaled_body;
                    hscale = ns;
                }
                if (spaces > 0 && Math.fabs (delta) > 0.01) space_extra += delta / spaces;
            }
            if (Math.fabs (letter_extra) > 0.001 || Math.fabs (space_extra) > 0.001) {
                foreach (var s in b.spans) {
                    int a = int.max (s.start, cl.start) - cl.start;
                    int e = int.min (s.end, cl.end) - cl.start;
                    if (e <= a) continue;
                    double track = s.fmt.tracking.is_nan () ? 0 : s.fmt.size * s.fmt.tracking / 1000.0;
                    if (Math.fabs (letter_extra) > 0.001) add (attrs, Pango.attr_letter_spacing_new ((int) ((track + letter_extra) * Pango.SCALE)), a, e);
                    if (Math.fabs (space_extra) > 0.001) {
                        int k = a;
                        while (k < e) {
                            int q = body.index_of_char (' ', k);
                            if (q < 0 || q >= e) break;
                            add (attrs, Pango.attr_letter_spacing_new ((int) ((track + letter_extra + space_extra / hscale) * Pango.SCALE)), q, q + 1);
                            k = q + 1;
                        }
                    }
                }
                layout = para_layout (b);
                layout.set_text (text, -1);
                layout.set_attributes (attrs);
                layout.set_width (-1);
                layout.set_tabs (tab_array (b, band.a - col.x, col.w));
                line = layout.get_line_readonly (0);
                line.get_extents (out ink, out logical);
            }
            var ll = new LaidLine ();
            ll.build = b;
            ll.para = b.para_index;
            ll.layout = layout;
            ll.window = cl.start;
            ll.disp_start = cl.start;
            ll.disp_end = cl.next;
            ll.start = b.story_of (cl.start);
            ll.end = cl.next >= b.text.length ? b.length_chars : b.story_of (cl.next);
            if (ll.end < ll.start) ll.end = ll.start;
            ll.x = band.a - hang_l;
            ll.width = width;
            ll.hscale = hscale;
            ll.composed = true;
            double drawn = logical.width / (double) Pango.SCALE * hscale;
            double off = 0;
            if (!justify_line) {
                if (align == TextAlign.CENTER) off = (width - drawn) / 2;
                else if (align == TextAlign.RIGHT || (pf.direction == 1 && align == TextAlign.JUSTIFY)) off = width - drawn;
            }
            ll.x_off = logical.x / (double) Pango.SCALE * hscale + off;
            var iter = layout.get_iter ();
            iter.get_line_extents (out ink, out logical);
            int bl = iter.get_baseline ();
            ll.ascent = (bl - logical.y) / (double) Pango.SCALE;
            ll.descent = (logical.y + logical.height - bl) / (double) Pango.SCALE;
            return ll;
        }

        private LaidLine make_drop (ParaBuild b, int drop_lines, double leading, out double drop_w) {
            int ds = b.prefix_bytes;
            int de = ds + b.drop_bytes;
            double body = b.base_cf.size;
            double cap = (drop_lines - 1) * leading + 0.7 * body;
            var sp = span_at (b, ds);
            var dcf = sp != null ? sp.fmt.clone () : b.base_cf.clone ();
            dcf.size = cap / 0.7;
            var dl = para_layout (b);
            dl.set_text (b.text.substring (ds, de - ds), -1);
            var al = attrs_for (b, ds, de);
            var fd = new Pango.AttrFontDesc (font_desc (dcf));
            fd.start_index = 0;
            fd.end_index = de - ds;
            al.change ((owned) fd);
            dl.set_attributes (al);
            Pango.Rectangle ink, logical;
            dl.get_line_readonly (0).get_extents (out ink, out logical);
            drop_w = (logical.x + logical.width) / (double) Pango.SCALE + body * 0.25;
            var drop = new LaidLine ();
            drop.build = b;
            drop.para = b.para_index;
            drop.start = 0;
            drop.end = b.story_of (de);
            drop.layout = dl;
            drop.window = ds;
            drop.disp_start = ds;
            drop.disp_end = de;
            drop.is_drop = true;
            drop.width = drop_w;
            drop.ascent = cap;
            drop.descent = 0;
            drop.para_first = true;
            return drop;
        }

        private Span? span_at (ParaBuild b, int disp) {
            foreach (var s in b.spans) if (disp >= s.start && disp < s.end) return s;
            if (b.spans.size > 0) return b.spans[b.spans.size - 1];
            return null;
        }

        private LaidLine? place_line (ParaBuild b, int from, int total, Band band, ColumnBox col) {
            double width = band.b - band.a;
            if (from >= total) return null;
            int win = int.min (total, from + 64 + (int) (width / 2.0) * 4);
            Pango.Layout layout;
            unowned Pango.LayoutLine line;
            while (true) {
                bool last_possible = win >= total;
                layout = make_layout (b, from, win, width, last_possible, band.a - col.x, col.w);
                line = layout.get_line_readonly (0);
                int used = line.start_index + line.length;
                if (layout.get_line_count () == 1 && win < total) {
                    win = int.min (total, win + 256);
                    continue;
                }
                if (used >= win - from && win < total) {
                    win = int.min (total, win + 256);
                    continue;
                }
                break;
            }
            if (layout.get_justify () && win < total) {
                string t = layout.get_text ();
                int e = int.min (t.length, line.start_index + line.length);
                bool gap = false;
                for (int i = line.start_index; i < e - 1; i++) {
                    if (t[i] == ' ' || t[i] == '\t') {
                        gap = true;
                        break;
                    }
                }
                if (!gap) {
                    layout.set_justify (false);
                    line = layout.get_line_readonly (0);
                }
            }
            var ll = new LaidLine ();
            ll.build = b;
            ll.para = b.para_index;
            ll.layout = layout;
            ll.window = from;
            ll.disp_start = from;
            ll.disp_end = from + line.start_index + line.length;
            ll.start = b.story_of (from);
            ll.end = ll.disp_end >= total ? b.length_chars : b.story_of (ll.disp_end);
            if (ll.end < ll.start) ll.end = ll.start;
            ll.x = band.a;
            ll.width = width;
            Pango.Rectangle ink, logical;
            var iter = layout.get_iter ();
            iter.get_line_extents (out ink, out logical);
            ll.x_off = logical.x / (double) Pango.SCALE;
            if (b.pf.optical == 1 && ll.disp_end > from) {
                double hl, hr;
                optical_hangs (b.text.substring (from, ll.disp_end - from), layout.get_line_readonly (0), out hl, out hr);
                if (b.pf.text_align () == TextAlign.RIGHT) ll.x += hr;
                else if (b.pf.text_align () != TextAlign.CENTER) ll.x -= hl;
            }
            int bl = iter.get_baseline ();
            ll.ascent = (bl - logical.y) / (double) Pango.SCALE;
            ll.descent = (logical.y + logical.height - bl) / (double) Pango.SCALE;
            collect_leaders (ll, layout, b, from, band.a - col.x);
            return ll;
        }

        private LaidLine empty_line (ParaBuild b, int from, Band band) {
            var layout = para_layout (b);
            layout.set_text ("", -1);
            layout.set_font_description (font_desc (b.base_cf));
            var ll = new LaidLine ();
            ll.build = b;
            ll.para = b.para_index;
            ll.layout = layout;
            ll.window = from;
            ll.disp_start = from;
            ll.disp_end = b.text.length;
            ll.start = 0;
            ll.end = b.length_chars;
            ll.x = band.a;
            ll.width = band.b - band.a;
            var align = b.pf.text_align ();
            if (align == TextAlign.CENTER) ll.x_off = ll.width / 2;
            else if (align == TextAlign.RIGHT) ll.x_off = ll.width;
            Pango.Rectangle ink, logical;
            var iter = layout.get_iter ();
            iter.get_line_extents (out ink, out logical);
            int bl = iter.get_baseline ();
            ll.ascent = double.max (b.base_cf.size * 0.95, (bl - logical.y) / (double) Pango.SCALE);
            ll.descent = double.max (b.base_cf.size * 0.25, (logical.y + logical.height - bl) / (double) Pango.SCALE);
            return ll;
        }

        private void collect_leaders (LaidLine ll, Pango.Layout layout, ParaBuild b, int from, double origin) {
            var stops = TabStop.parse (b.pf.tabs);
            bool any = false;
            foreach (var t in stops) if (t.leader != "") any = true;
            if (!any) return;
            string t = layout.get_text ();
            unowned Pango.LayoutLine line = layout.get_line_readonly (0);
            int end = line.start_index + line.length;
            for (int i = line.start_index; i < end && i < t.length; i++) {
                if (t[i] != '\t') continue;
                if (b.has_prefix_tab && from + i < b.prefix_bytes) continue;
                int x0, x1;
                line.index_to_x (i, false, out x0);
                line.index_to_x (i, true, out x1);
                double a = x0 / (double) Pango.SCALE, e = x1 / (double) Pango.SCALE;
                TabStop? hit = null;
                foreach (var ts in stops) {
                    double p = ts.pos - origin;
                    if (p > a + 0.5) {
                        hit = ts;
                        break;
                    }
                }
                if (hit == null || hit.leader == "" || e - a < 2) continue;
                var sp = span_at (b, from + i);
                ll.leaders.add (new Leader (a, e, hit.leader, sp != null ? sp.fmt : b.base_cf));
            }
        }

        private bool has_notes (FrameResult fr, int column) {
            foreach (var n in fr.notes) if (n.column == column) return true;
            return false;
        }

        public double reserved (FrameResult fr, int column) {
            double h = 0;
            bool any = false;
            foreach (var n in fr.notes) {
                if (n.column != column) continue;
                h += n.height + (any ? pub.footnotes.space_between : pub.footnotes.space_before);
                any = true;
            }
            return h;
        }

        private NoteBlock note_block (NoteRef nr, ColumnBox col, int column) {
            var nb = new NoteBlock ();
            nb.column = column;
            nb.number = nr.number;
            nb.note = nr.note;
            nb.x = col.x;
            nb.w = col.w;
            nb.col_bottom = col.y + col.h;
            var prepared = Footnotes.prepared (pub, nr.note, nr.number);
            var saved = font_scale;
            nb.box = layout_box (prepared, col.w, 100000);
            font_scale = saved;
            nb.height = nb.box.content_height;
            return nb;
        }

        private NoteBlock? split_note (NoteBlock nb, double room) {
            var keep = new Gee.ArrayList<LaidLine> ();
            var move = new Gee.ArrayList<LaidLine> ();
            foreach (var l in nb.box.lines) {
                if (move.size == 0 && l.baseline + l.descent <= room + 0.01) keep.add (l);
                else move.add (l);
            }
            if (keep.size == 0 || move.size == 0) return null;
            double shift = move[0].baseline - move[0].ascent;
            foreach (var l in move) l.baseline -= shift;
            var head = new FrameResult (null);
            head.lines.add_all (keep);
            var tail = new FrameResult (null);
            tail.lines.add_all (move);
            foreach (var fr in new FrameResult[] { head, tail }) {
                double h = 0;
                foreach (var l in fr.lines) h = double.max (h, l.baseline + l.descent);
                fr.content_height = h;
                fr.empty = false;
            }
            var rest = new NoteBlock ();
            rest.number = nb.number;
            rest.note = nb.note;
            rest.box = tail;
            rest.height = tail.content_height;
            rest.continued = true;
            nb.box = head;
            nb.height = head.content_height;
            return rest;
        }

        private void place_notes (FrameResult fr) {
            var cols = new Gee.HashSet<int> ();
            foreach (var n in fr.notes) cols.add (n.column);
            foreach (int c in cols) {
                double total = 0;
                bool any = false;
                double bottom = 0;
                foreach (var n in fr.notes) {
                    if (n.column != c) continue;
                    total += n.height + (any ? pub.footnotes.space_between : 0);
                    any = true;
                    bottom = n.col_bottom;
                }
                double y = bottom - total;
                foreach (var n in fr.notes) {
                    if (n.column != c) continue;
                    n.y = y;
                    y += n.height + pub.footnotes.space_between;
                }
            }
        }

        private void finish_frame (FrameResult fr, Gee.HashMap<int, Gee.ArrayList<ColumnBox>> col_cache) {
            place_notes (fr);
            fr.empty = fr.lines.size == 0;
            if (fr.empty) return;
            double bottom = 0;
            foreach (var l in fr.lines) bottom = double.max (bottom, l.baseline + l.descent);
            fr.content_height = bottom;
            var f = fr.frame;
            fr.first = TextPos (fr.lines[0].para, fr.lines[0].start);
            var last = fr.lines[fr.lines.size - 1];
            foreach (var l in fr.lines) if (!l.is_drop && (l.para > last.para || (l.para == last.para && l.end >= last.end))) last = l;
            fr.last = TextPos (last.para, last.end);
            if (f == null || f.valign == 0 || f.auto_height) return;
            var columns = columns_of (f);
            for (int c = 0; c < columns.size; c++) {
                var col = columns[c];
                double top = double.MAX, bot = -double.MAX;
                int count = 0;
                foreach (var l in fr.lines) {
                    if (l.column != c) continue;
                    top = double.min (top, l.baseline - l.ascent);
                    bot = double.max (bot, l.baseline + l.descent);
                    count++;
                }
                if (count == 0) continue;
                double slack = col.y + col.h - reserved (fr, c) - bot;
                if (slack <= 0) continue;
                if (f.valign == 3) {
                    var baselines = new Gee.ArrayList<double?> ();
                    foreach (var l in fr.lines) if (l.column == c && !baselines.contains (l.baseline)) baselines.add (l.baseline);
                    if (baselines.size < 2) continue;
                    baselines.sort ((a, b) => a < b ? -1 : (a > b ? 1 : 0));
                    double per = slack / (baselines.size - 1);
                    foreach (var l in fr.lines) {
                        if (l.column != c) continue;
                        int idx = 0;
                        for (int k = 0; k < baselines.size; k++) if (Math.fabs (baselines[k] - l.baseline) < 0.001) idx = k;
                        l.baseline += per * idx;
                    }
                    continue;
                }
                double shift = f.valign == 1 ? slack / 2 : slack;
                foreach (var l in fr.lines) if (l.column == c) l.baseline += shift;
            }
        }
    }
}
