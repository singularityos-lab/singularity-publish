using Gtk;

namespace Singularity.Apps.Publish {

    public enum Tool {
        SELECT,
        CONTENT,
        TEXT,
        IMAGE_FRAME,
        RECT,
        ELLIPSE,
        POLYGON,
        STAR,
        LINE,
        TABLE,
        HAND,
        FREEFORM,
        PEN
    }

    public enum DragKind {
        NONE,
        MOVE,
        RESIZE,
        ROTATE,
        RUBBER,
        CREATE,
        PAN,
        GUIDE,
        TEXT_SELECT,
        CONTENT_PAN,
        CONTENT_SCALE,
        TABLE_COL,
        TABLE_ROW,
        FREEHAND,
        WRAP_POINT,
        PEN_HANDLE
    }

    public class PageSlot {
        public int page;
        public bool left;
        public double x;
        public double y;
        public int spread;
        public double w = 0;
        public double h = 0;

        public PageSlot (int page, bool left, double x, double y, int spread) {
            this.page = page;
            this.left = left;
            this.x = x;
            this.y = y;
            this.spread = spread;
        }
    }

    private class DragOrig {
        public Item item;
        public Item copy;

        public DragOrig (Item item) {
            this.item = item;
            copy = item.clone ();
        }
    }

    public class PageCanvas : Widget, Scrollable {
        public signal void selection_changed ();
        public signal void edited ();
        public signal void text_changed ();
        public signal void page_changed ();
        public signal void context_requested (double x, double y);
        public signal void zoom_changed ();
        public signal void tool_changed ();
        public signal void item_double_clicked (Item item);
        public signal void page_pointer (int page, double x, double y);
        public Item? wrap_item = null;
        private int wrap_handle = -1;
        private Gee.ArrayList<Point?> free_pts = new Gee.ArrayList<Point?> ();
        private Gee.ArrayList<Point?> pen_pts = new Gee.ArrayList<Point?> ();
        private Gee.ArrayList<Point?> pen_handles = new Gee.ArrayList<Point?> ();
        private PageSlot? pen_slot = null;

        public Document? doc = null;
        public LayoutCache cache;
        public Renderer renderer;
        public bool master_mode = false;
        public string master_id = "A";
        public Tool tool = Tool.SELECT;
        public Gee.ArrayList<Item> selection = new Gee.ArrayList<Item> ();
        public int sel_page = 0;
        public bool sel_left = false;
        public EditState? edit = null;
        public ImageFrame? content_frame = null;
        public TextFrame? thread_from = null;
        public int cell_r1 = -1;
        public int cell_c1 = -1;
        public int cell_r2 = -1;
        public int cell_c2 = -1;
        public bool show_rulers = true;
        public bool show_guides = true;
        public bool snap = true;
        public bool smart = true;
        public bool show_baseline = false;
        public bool frame_edges = true;
        public bool preview = false;
        public bool separations = false;
        public Gee.HashSet<string> sep_enabled = new Gee.HashSet<string> ();
        private Gee.HashMap<int, SeparationPreview> sep_cache = new Gee.HashMap<int, SeparationPreview> ();

        public SeparationPreview? separation_for (int page) {
            if (!separations || pub == null || page < 0) return null;
            if (!sep_cache.has_key (page)) {
                var sp = new SeparationPreview (pub);
                sp.render (page, 2);
                sep_cache[page] = sp;
            }
            var s = sep_cache[page];
            bool changed = s.enabled.size != sep_enabled.size;
            if (!changed) foreach (string e in sep_enabled) if (!s.enabled.contains (e)) changed = true;
            if (changed) {
                s.enabled.clear ();
                s.enabled.add_all (sep_enabled);
                s.build_composite ();
            }
            return s;
        }

        public void drop_separations () {
            sep_cache.clear ();
        }
        public bool hidden_chars = false;
        public double scale = 1;
        public string units = "mm";

        private Adjustment? _hadj = null;
        private Adjustment? _vadj = null;
        public Gee.ArrayList<PageSlot> slots = new Gee.ArrayList<PageSlot> ();
        private double wx0 = 0;
        private double wy0 = 0;
        private double wx1 = 100;
        private double wy1 = 100;
        private double off_x = 0;
        private double off_y = 0;
        private const double GAP = 36;
        private const double PASTE = 180;
        public const int RULER = CanvasRulers.SIZE;
        private CanvasRulers rulers;
        private const double HANDLE = 7;
        private DragKind drag = DragKind.NONE;
        private int handle_x = 0;
        private int handle_y = 0;
        private double press_wx = 0;
        private double press_wy = 0;
        private double press_px = 0;
        private double press_py = 0;
        private bool drag_started = false;
        private bool drag_copy = false;
        private bool shift_down = false;
        private Gee.ArrayList<DragOrig> origs = new Gee.ArrayList<DragOrig> ();
        private Rect orig_bounds;
        private double cur_wx = 0;
        private double cur_wy = 0;
        private Gee.ArrayList<double?> snap_vx = new Gee.ArrayList<double?> ();
        private Gee.ArrayList<double?> snap_hy = new Gee.ArrayList<double?> ();
        private Guide? drag_guide = null;
        private Gee.ArrayList<Guide>? drag_guide_list = null;
        private bool new_guide_vertical = false;
        private PageSlot? drag_slot = null;
        private double pan_h0 = 0;
        private double pan_v0 = 0;
        private int table_line = -1;
        private double table_orig = 0;
        private double table_next = 0;
        private IMMulticontext im;
        private EventControllerKey key_ctl;
        private bool caret_on = true;
        private uint blink_id = 0;
        private int click_count = 0;
        private bool pending_center = true;
        public bool auto_fit = true;
        public bool fit_spread = false;
        private int last_w = 0;
        private int last_h = 0;
        private uint fit_idle = 0;

        public Adjustment hadjustment {
            get { return _hadj; }
            set construct {
                if (_hadj != null) _hadj.value_changed.disconnect (on_adj);
                _hadj = value;
                if (_hadj != null) _hadj.value_changed.connect (on_adj);
                queue_allocate ();
            }
        }

        public Adjustment vadjustment {
            get { return _vadj; }
            set construct {
                if (_vadj != null) _vadj.value_changed.disconnect (on_adj);
                _vadj = value;
                if (_vadj != null) _vadj.value_changed.connect (on_adj);
                queue_allocate ();
            }
        }

        public ScrollablePolicy hscroll_policy { get; set; }
        public ScrollablePolicy vscroll_policy { get; set; }

        public bool get_border (out Border border) {
            border = Border ();
            return false;
        }

        private void on_adj () {
            queue_draw ();
        }

        public PageCanvas () {
            focusable = true;
            can_focus = true;
            hexpand = true;
            vexpand = true;
            overflow = Overflow.HIDDEN;
            rulers = new CanvasRulers (this);
            var click = new GestureClick ();
            click.button = 0;
            click.pressed.connect (on_pressed);
            click.released.connect ((n, x, y) => {
                if (click.get_current_button () == Gdk.BUTTON_SECONDARY) return;
            });
            add_controller (click);
            var dg = new GestureDrag ();
            dg.button = 0;
            dg.drag_begin.connect (on_drag_begin);
            dg.drag_update.connect (on_drag_update);
            dg.drag_end.connect (on_drag_end);
            add_controller (dg);
            var motion = new EventControllerMotion ();
            motion.motion.connect (on_motion);
            add_controller (motion);
            var keys = new EventControllerKey ();
            keys.key_pressed.connect (on_key);
            keys.key_released.connect ((kv, kc, st) => {
                shift_down = (st & Gdk.ModifierType.SHIFT_MASK) != 0 && kv != Gdk.Key.Shift_L && kv != Gdk.Key.Shift_R;
            });
            add_controller (keys);
            im = new IMMulticontext ();
            im.commit.connect (on_commit);
            key_ctl = keys;
            var focus = new EventControllerFocus ();
            focus.enter.connect (() => im.focus_in ());
            focus.leave.connect (() => im.focus_out ());
            add_controller (focus);
            var scroll = new EventControllerScroll (EventControllerScrollFlags.BOTH_AXES);
            scroll.scroll.connect (on_scroll);
            add_controller (scroll);
            var zoom_gesture = new GestureZoom ();
            double zoom0 = 1;
            zoom_gesture.begin.connect (() => zoom0 = scale);
            zoom_gesture.scale_changed.connect ((s) => zoom_to (zoom0 * s));
            add_controller (zoom_gesture);
        }

        public Publication? pub {
            owned get { return doc != null ? doc.pub : null; }
        }

        public void set_document (Document? d) {
            doc = d;
            edit = null;
            content_frame = null;
            thread_from = null;
            selection.clear ();
            master_mode = false;
            sel_page = 0;
            sel_left = false;
            if (d != null) {
                cache = new LayoutCache (d.pub);
                renderer = new Renderer (d.pub, cache);
                units = d.pub.settings.units;
            }
            pending_center = true;
            auto_fit = true;
            relayout ();
            queue_allocate ();
            queue_draw ();
        }

        public void rebind () {
            if (doc == null) return;
            cache = new LayoutCache (doc.pub);
            renderer = new Renderer (doc.pub, cache);
            relayout ();
            queue_allocate ();
            queue_draw ();
        }

        public void invalidate () {
            if (doc == null) return;
            if (cache.pub != doc.pub) {
                rebind ();
                return;
            }
            cache.invalidate ();
            sep_cache.clear ();
            queue_draw ();
        }

        public void relayout () {
            slots.clear ();
            if (pub == null) return;
            var s = pub.settings;
            double y = 0;
            double maxw = s.width * 2;
            if (master_mode) {
                if (s.facing) {
                    slots.add (new PageSlot (-1, true, -s.width, 0, 0));
                    slots.add (new PageSlot (-1, false, 0, 0, 0));
                } else {
                    slots.add (new PageSlot (-1, false, -s.width / 2, 0, 0));
                }
                foreach (var sl in slots) {
                    sl.w = s.width;
                    sl.h = s.height;
                }
                y = s.height;
            } else {
                var spreads = pub.spreads ();
                for (int i = 0; i < spreads.size; i++) {
                    var sp = spreads[i];
                    double x;
                    double first_w = pub.page_w (sp.pages[0]);
                    double total = 0, row_h = 0;
                    foreach (int p in sp.pages) {
                        total += pub.page_w (p);
                        row_h = double.max (row_h, pub.page_h (p));
                    }
                    if (s.facing) x = sp.first_is_left ? -first_w : 0;
                    else x = -total / 2;
                    foreach (int p in sp.pages) {
                        var sl = new PageSlot (p, pub.is_left_page (p), x, y, i);
                        sl.w = pub.page_w (p);
                        sl.h = pub.page_h (p);
                        slots.add (sl);
                        x += sl.w;
                        maxw = double.max (maxw, 2 * double.max (x.abs (), (x - total).abs ()));
                    }
                    y += row_h + GAP;
                }
                y -= GAP;
            }
            wx0 = -maxw / 2 - PASTE;
            wx1 = maxw / 2 + PASTE;
            wy0 = -PASTE / 2;
            wy1 = y + PASTE / 2;
        }

        public PageSlot? slot_for (int page, bool left = false) {
            foreach (var s in slots) {
                if (s.page == page && (page >= 0 || s.left == left)) return s;
            }
            if (page < 0 && slots.size > 0) return slots[slots.size - 1];
            return null;
        }

        public Gee.ArrayList<Item> items_for_slot (PageSlot s) {
            if (s.page >= 0) return pub.pages[s.page].items;
            var m = pub.master (master_id);
            if (m == null) return new Gee.ArrayList<Item> ();
            return m.items_for (s.left && pub.settings.facing);
        }

        public Gee.ArrayList<Item> active_list () {
            if (pub == null) return new Gee.ArrayList<Item> ();
            if (master_mode) {
                var m = pub.master (master_id);
                if (m == null) return new Gee.ArrayList<Item> ();
                return m.items_for (sel_left && pub.settings.facing);
            }
            int p = sel_page.clamp (0, pub.pages.size - 1);
            return pub.pages[p].items;
        }

        public PageSlot? active_slot () {
            return master_mode ? slot_for (-1, sel_left) : slot_for (sel_page);
        }

        public int active_page_index () {
            if (master_mode || pub == null) return -1;
            sel_page = sel_page.clamp (0, pub.pages.size - 1);
            return sel_page;
        }

        public override void size_allocate (int width, int height, int baseline) {
            if (pub == null) return;
            double cw = (wx1 - wx0) * scale, ch = (wy1 - wy0) * scale;
            if (_hadj != null) {
                double v = _hadj.value;
                _hadj.configure (v.clamp (0, double.max (0, cw - width)), 0, double.max (cw, width), width * 0.1, width * 0.9, width);
            }
            if (_vadj != null) {
                double v = _vadj.value;
                _vadj.configure (v.clamp (0, double.max (0, ch - height)), 0, double.max (ch, height), height * 0.1, height * 0.9, height);
            }
            bool resized = width != last_w || height != last_h;
            last_w = width;
            last_h = height;
            if ((pending_center || (auto_fit && resized)) && width > 1 && height > 1) {
                pending_center = false;
                if (fit_idle != 0) Source.remove (fit_idle);
                fit_idle = Idle.add (() => {
                    fit_idle = 0;
                    if (fit_spread) zoom_fit_spread ();
                    else zoom_fit_page ();
                    auto_fit = true;
                    return Source.REMOVE;
                });
            }
        }

        private void compute_offsets () {
            int w = get_width (), h = get_height ();
            double cw = (wx1 - wx0) * scale, ch = (wy1 - wy0) * scale;
            off_x = cw < w ? (w - cw) / 2 : -(_hadj != null ? _hadj.value : 0);
            off_y = ch < h ? (h - ch) / 2 : -(_vadj != null ? _vadj.value : 0);
        }

        public void to_world (double px, double py, out double wx, out double wy) {
            compute_offsets ();
            wx = (px - off_x) / scale + wx0;
            wy = (py - off_y) / scale + wy0;
        }

        public void to_widget (double wx, double wy, out double px, out double py) {
            compute_offsets ();
            px = (wx - wx0) * scale + off_x;
            py = (wy - wy0) * scale + off_y;
        }

        public PageSlot? slot_at (double wx, double wy) {
            PageSlot? best = null;
            double bd = double.MAX;
            var s = pub.settings;
            foreach (var sl in slots) {
                double cx = double.max (sl.x - wx, double.max (0, wx - (sl.x + sl.w)));
                double cy = double.max (sl.y - wy, double.max (0, wy - (sl.y + sl.h)));
                double d = cx * cx * 0.25 + cy * cy;
                if (d < bd) {
                    bd = d;
                    best = sl;
                }
            }
            return best;
        }

        public void zoom_to (double z, double anchor_px = -1, double anchor_py = -1) {
            if (pub == null) return;
            auto_fit = false;
            z = z.clamp (0.05, 40);
            double ax = anchor_px >= 0 ? anchor_px : get_width () / 2.0;
            double ay = anchor_py >= 0 ? anchor_py : get_height () / 2.0;
            double wx, wy;
            to_world (ax, ay, out wx, out wy);
            scale = z;
            size_allocate (get_width (), get_height (), -1);
            center_on (wx, wy, ax, ay);
            zoom_changed ();
            queue_draw ();
        }

        public void center_on (double wx, double wy, double at_px = -1, double at_py = -1) {
            if (at_px < 0) at_px = get_width () / 2.0;
            if (at_py < 0) at_py = get_height () / 2.0;
            if (_hadj != null) _hadj.value = ((wx - wx0) * scale - at_px).clamp (0, double.max (0, _hadj.upper - _hadj.page_size));
            if (_vadj != null) _vadj.value = ((wy - wy0) * scale - at_py).clamp (0, double.max (0, _vadj.upper - _vadj.page_size));
            queue_draw ();
        }

        public void zoom_fit_page () {
            if (pub == null || get_width () < 10) return;
            var sl = active_slot () ?? (slots.size > 0 ? slots[0] : null);
            if (sl == null) return;
            double w = sl.w, h = sl.h;
            double avail_w = get_width () - (show_rulers ? RULER : 0) - 48, avail_h = get_height () - (show_rulers ? RULER : 0) - 48;
            scale = double.min (avail_w / w, avail_h / h).clamp (0.05, 40);
            size_allocate (get_width (), get_height (), -1);
            center_on (sl.x + w / 2, sl.y + h / 2, get_width () / 2.0 + (show_rulers ? RULER / 2 : 0), get_height () / 2.0 - (show_rulers ? RULER / 2 : 0));
            zoom_changed ();
        }

        public void zoom_fit_spread () {
            if (pub == null || get_width () < 10) return;
            var sl = active_slot ();
            if (sl == null) return;
            double x0 = double.MAX, x1 = -double.MAX;
            foreach (var s in slots) if (s.spread == sl.spread && s.y == sl.y) {
                x0 = double.min (x0, s.x);
                x1 = double.max (x1, s.x + s.w);
            }
            double w = x1 - x0, h = sl.h;
            scale = double.min ((get_width () - 60 - (show_rulers ? RULER : 0)) / w, (get_height () - 60 - (show_rulers ? RULER : 0)) / h).clamp (0.05, 40);
            size_allocate (get_width (), get_height (), -1);
            center_on ((x0 + x1) / 2, sl.y + h / 2, get_width () / 2.0 + (show_rulers ? RULER / 2 : 0), get_height () / 2.0 - (show_rulers ? RULER / 2 : 0));
            zoom_changed ();
        }

        public void show_page (int index) {
            if (pub == null) return;
            sel_page = index.clamp (0, pub.pages.size - 1);
            var sl = slot_for (sel_page);
            if (sl == null) return;
            double wx, wy;
            to_world (0, 0, out wx, out wy);
            double top = wy, bottom = wy + get_height () / scale;
            if (sl.y < top || sl.y + sl.h > bottom) center_on (sl.x + sl.w / 2, sl.y + sl.h / 2);
            queue_draw ();
        }

        private bool on_scroll (EventControllerScroll c, double dx, double dy) {
            var st = c.get_current_event_state ();
            auto_fit = false;
            if ((st & Gdk.ModifierType.CONTROL_MASK) != 0) {
                double px = cur_px, py = cur_py;
                zoom_to (scale * (dy < 0 ? 1.12 : 1 / 1.12), px, py);
                return true;
            }
            if (content_frame != null && (st & Gdk.ModifierType.ALT_MASK) != 0) {
                scale_content (dy < 0 ? 1.05 : 1 / 1.05);
                return true;
            }
            double step = 40;
            if ((st & Gdk.ModifierType.SHIFT_MASK) != 0) {
                double t = dx;
                dx = dy;
                dy = t;
            }
            if (_hadj != null) _hadj.value = (_hadj.value + dx * step).clamp (0, double.max (0, _hadj.upper - _hadj.page_size));
            if (_vadj != null) _vadj.value = (_vadj.value + dy * step).clamp (0, double.max (0, _vadj.upper - _vadj.page_size));
            update_current_page_from_view ();
            return true;
        }

        private void update_current_page_from_view () {
            if (pub == null || master_mode) return;
            double wx, wy;
            to_world (get_width () / 2.0, get_height () / 2.0, out wx, out wy);
            var sl = slot_at (wx, wy);
            if (sl != null && sl.page >= 0 && sl.page != doc.current_page && edit == null && selection.size == 0) {
                doc.current_page = sl.page;
                sel_page = sl.page;
                page_changed ();
            }
        }

        public double cur_px = 0;
        public double cur_py = 0;

        public override void snapshot (Gtk.Snapshot snap) {
            var rect = Graphene.Rect ();
            rect.init (0, 0, get_width (), get_height ());
            var clip = Gsk.RoundedRect ();
            clip.init_from_rect (rect, 12);
            snap.push_rounded_clip (clip);
            paint (snap, rect);
            snap.pop ();
        }

        private void paint (Gtk.Snapshot snap, Graphene.Rect rect) {
            int w = get_width (), h = get_height ();
            var cr = snap.append_cairo (rect);
            var fg = get_color ();
            cr.set_source_rgba (fg.red, fg.green, fg.blue, 0.06);
            cr.paint ();
            if (pub == null) return;
            compute_offsets ();
            cr.save ();
            cr.translate (off_x - wx0 * scale, off_y - wy0 * scale);
            cr.scale (scale, scale);
            double vx0, vy0, vx1, vy1;
            to_world (0, 0, out vx0, out vy0);
            to_world (w, h, out vx1, out vy1);
            var s = pub.settings;
            renderer.opts.print = false;
            renderer.opts.frame_edges = frame_edges && !preview;
            renderer.opts.overset_marks = !preview;
            renderer.opts.placeholders = !preview;
            var sel_ids = new Gee.HashSet<int> ();
            foreach (var it in selection) sel_ids.add (it.id);
            renderer.opts.selected = sel_ids;
            foreach (var sl in slots) {
                double bl = s.max_bleed ();
                if (sl.x + sl.w + bl < vx0 || sl.x - bl > vx1 || sl.y + sl.h + bl < vy0 || sl.y - bl > vy1) continue;
                cr.save ();
                cr.translate (sl.x, sl.y);
                cr.set_source_rgba (0, 0, 0, 0.18);
                cr.rectangle (1.5 / scale, 2 / scale, sl.w, sl.h);
                cr.fill ();
                if (preview) {
                    cr.rectangle (0, 0, sl.w, sl.h);
                    cr.clip ();
                }
                var sep = sl.page >= 0 ? separation_for (sl.page) : null;
                if (sep != null && sep.composite != null) {
                    cr.save ();
                    cr.scale (1 / sep.scale, 1 / sep.scale);
                    cr.set_source_surface (sep.composite, 0, 0);
                    cr.paint ();
                    cr.restore ();
                } else if (sl.page >= 0) renderer.draw_page (cr, sl.page, true);
                else {
                    var m = pub.master (master_id);
                    if (m != null) renderer.draw_master (cr, m, sl.left);
                }
                if (!preview) draw_page_overlays (cr, sl);
                if (!preview && sl.page >= 0) draw_comments (cr, sl.page);
                cr.restore ();
            }
            if (!preview && !master_mode && pub.merge.catalogue && pub.merge.active ()) {
                var sl0 = slot_for (0);
                if (sl0 != null) {
                    cr.save ();
                    cr.translate (sl0.x, sl0.y);
                    cr.set_source_rgba (0.95, 0.45, 0.1, 0.9);
                    cr.set_line_width (1.5 / scale);
                    cr.set_dash ({ 6 / scale, 3 / scale }, 0);
                    var a = pub.merge.area ();
                    cr.rectangle (a.x, a.y, a.w, a.h);
                    cr.stroke ();
                    cr.restore ();
                }
            }
            draw_selection (cr);
            draw_edit (cr);
            draw_feedback (cr);
            cr.restore ();
            if (show_rulers && !preview) rulers.draw (cr, w, h);
        }

        private void draw_comments (Cairo.Context cr, int page) {
            foreach (var c in pub.comments) {
                if (c.page != page) continue;
                double a = c.resolved ? 0.35 : 0.95;
                if (c.w > 1 && c.h > 1 && c.kind != "Text") {
                    cr.set_source_rgba (1, 0.85, 0.1, 0.3 * a);
                    cr.rectangle (c.x, c.y, c.w, c.h);
                    cr.fill ();
                }
                double s = 14 / scale;
                cr.set_source_rgba (1, 0.78, 0.05, a);
                cr.rectangle (c.x, c.y, s, s * 0.8);
                cr.fill ();
                cr.move_to (c.x + s * 0.2, c.y + s * 0.8);
                cr.line_to (c.x + s * 0.2, c.y + s * 1.05);
                cr.line_to (c.x + s * 0.5, c.y + s * 0.8);
                cr.close_path ();
                cr.fill ();
            }
        }

        private void draw_page_overlays (Cairo.Context cr, PageSlot sl) {
            var s = pub.settings;
            double lw = 1 / scale;
            cr.set_line_width (lw);
            if (s.max_bleed () > 0) {
                var b = sl.page >= 0 ? pub.bleed_rect (sl.page) : Rect (-s.bleed_inside, -s.bleed_top, s.width + s.bleed_inside + s.bleed_outside, s.height + s.bleed_top + s.bleed_bottom);
                cr.set_source_rgba (0.9, 0.2, 0.2, 0.7);
                cr.rectangle (b.x, b.y, b.w, b.h);
                cr.stroke ();
            }
            if (!show_guides) return;
            int pi = sl.page >= 0 ? sl.page : (sl.left ? 0 : 1);
            Rect m;
            Gee.ArrayList<Rect?> cols;
            if (sl.page >= 0) {
                m = pub.margin_rect (sl.page);
                cols = pub.column_rects (sl.page);
            } else {
                double ml = s.facing && sl.left ? s.margin_outside : s.margin_inside;
                double mr = s.facing && sl.left ? s.margin_inside : s.margin_outside;
                m = Rect (ml, s.margin_top, s.width - ml - mr, s.height - s.margin_top - s.margin_bottom);
                cols = new Gee.ArrayList<Rect?> ();
                int n = int.max (1, s.columns);
                double cw = (m.w - s.gutter * (n - 1)) / n;
                for (int i = 0; i < n; i++) cols.add (Rect (m.x + i * (cw + s.gutter), m.y, cw, m.h));
            }
            if (show_baseline && s.baseline_step > 2) {
                cr.set_source_rgba (0.35, 0.65, 0.95, 0.35);
                for (double y = s.baseline_start; y < sl.h; y += s.baseline_step) {
                    cr.move_to (0, y);
                    cr.line_to (sl.w, y);
                }
                cr.stroke ();
            }
            if (show_baseline && sl.page >= 0) {
                foreach (var it in pub.pages[sl.page].items) {
                    var tf = it as TextFrame;
                    if (tf == null || !tf.own_grid || tf.grid_step < 2) continue;
                    Rgba col;
                    if (!Rgba.parse_hex (tf.grid_color, out col)) col = Rgba (0.6, 0.76, 0.95);
                    cr.save ();
                    renderer.transform (cr, tf);
                    cr.rectangle (0, 0, tf.w, tf.h);
                    cr.clip ();
                    cr.set_source_rgba (col.r, col.g, col.b, 0.6);
                    for (double y = tf.grid_start; y < tf.h; y += tf.grid_step) {
                        cr.move_to (0, y);
                        cr.line_to (tf.w, y);
                    }
                    cr.stroke ();
                    cr.restore ();
                }
            }
            cr.set_source_rgba (0.85, 0.2, 0.75, 0.8);
            cr.rectangle (m.x, m.y, m.w, m.h);
            cr.stroke ();
            if (cols.size > 1) {
                cr.set_source_rgba (0.55, 0.3, 0.9, 0.75);
                for (int i = 0; i < cols.size - 1; i++) {
                    double x1 = cols[i].x + cols[i].w, x2 = cols[i + 1].x;
                    cr.move_to (x1, m.y);
                    cr.line_to (x1, m.y + m.h);
                    cr.move_to (x2, m.y);
                    cr.line_to (x2, m.y + m.h);
                }
                cr.stroke ();
            }
            cr.set_source_rgba (0.1, 0.75, 0.9, 0.9);
            foreach (var g in guides_for (sl)) {
                if (g.vertical) {
                    cr.move_to (g.pos, -PASTE / 3);
                    cr.line_to (g.pos, sl.h + PASTE / 3);
                } else {
                    cr.move_to (-PASTE / 2, g.pos);
                    cr.line_to (sl.w + PASTE / 2, g.pos);
                }
            }
            cr.stroke ();
            if (pi < 0) return;
        }

        public Gee.ArrayList<Guide> guides_for (PageSlot sl) {
            var list = new Gee.ArrayList<Guide> ();
            if (sl.page >= 0) {
                var pg = pub.pages[sl.page];
                if (!pg.hide_master) foreach (var m in pub.master_chain (pg.master)) list.add_all (m.guides);
                list.add_all (pg.guides);
            } else {
                var m = pub.master (master_id);
                if (m != null) foreach (var mm in pub.master_chain (m.id)) list.add_all (mm.guides);
            }
            return list;
        }

        public Gee.ArrayList<Guide> own_guides (PageSlot sl) {
            if (sl.page >= 0) return pub.pages[sl.page].guides;
            var m = pub.master (master_id);
            return m != null ? m.guides : new Gee.ArrayList<Guide> ();
        }

        private void item_path (Cairo.Context cr, Item it) {
            var pts = new Gee.ArrayList<Point?> ();
            pts.add (it.to_page (0, 0));
            pts.add (it.to_page (it.w, 0));
            pts.add (it.to_page (it.w, it.h));
            pts.add (it.to_page (0, it.h));
            cr.move_to (pts[0].x, pts[0].y);
            for (int i = 1; i < 4; i++) cr.line_to (pts[i].x, pts[i].y);
            cr.close_path ();
        }

        private void draw_selection (Cairo.Context cr) {
            var sl = active_slot ();
            if (sl == null || preview) return;
            double lw = 1 / scale;
            cr.save ();
            cr.translate (sl.x, sl.y);
            var layer_color = Rgba (0.2, 0.45, 0.95, 1);
            foreach (var it in selection) {
                var l = pub.layer (it.layer);
                Rgba c = layer_color;
                if (l != null) Rgba.parse_hex (l.color, out c);
                cr.set_source_rgba (c.r, c.g, c.b, 1);
                cr.set_line_width (lw);
                item_path (cr, it);
                cr.stroke ();
                if (it is TextFrame) draw_ports (cr, (TextFrame) it, c);
                if (it is TableItem && cell_r1 >= 0) draw_cell_selection (cr, (TableItem) it);
            }
            if (selection.size == 1 && content_frame == null && edit == null) {
                var it = selection[0];
                if (!it.locked) {
                    double hs = HANDLE / scale;
                    for (int hy = 0; hy < 3; hy++) for (int hx = 0; hx < 3; hx++) {
                        if (hx == 1 && hy == 1) continue;
                        var p = it.to_page (it.w * hx / 2.0, it.h * hy / 2.0);
                        cr.rectangle (p.x - hs / 2, p.y - hs / 2, hs, hs);
                        cr.set_source_rgb (1, 1, 1);
                        cr.fill_preserve ();
                        cr.set_source_rgba (layer_color.r, layer_color.g, layer_color.b, 1);
                        cr.stroke ();
                    }
                    var top = it.to_page (it.w / 2, 0);
                    var rot = it.to_page (it.w / 2, -22 / scale);
                    cr.move_to (top.x, top.y);
                    cr.line_to (rot.x, rot.y);
                    cr.stroke ();
                    cr.arc (rot.x, rot.y, hs / 1.6, 0, 2 * Math.PI);
                    cr.set_source_rgb (1, 1, 1);
                    cr.fill_preserve ();
                    cr.set_source_rgba (layer_color.r, layer_color.g, layer_color.b, 1);
                    cr.stroke ();
                } else {
                    var p = it.to_page (it.w, 0);
                    cr.set_source_rgba (0.5, 0.5, 0.5, 1);
                    cr.rectangle (p.x - 3 / scale, p.y - 3 / scale, 6 / scale, 6 / scale);
                    cr.fill ();
                }
            } else if (selection.size > 1) {
                var b = selection_bounds ();
                cr.set_source_rgba (layer_color.r, layer_color.g, layer_color.b, 0.8);
                cr.set_dash ({ 4 / scale, 3 / scale }, 0);
                cr.rectangle (b.x, b.y, b.w, b.h);
                cr.stroke ();
                cr.set_dash (null, 0);
            }
            if (content_frame != null) {
                var inf = ImageStore.get_default ().info (pub, content_frame);
                if (inf != null) {
                    var pl = ImageStore.place (content_frame, inf);
                    cr.save ();
                    renderer.transform (cr, content_frame);
                    cr.set_source_rgba (0.95, 0.55, 0.1, 1);
                    cr.set_line_width (lw);
                    cr.rectangle (pl.ox, pl.oy, inf.width * pl.sx, inf.height * pl.sy);
                    cr.stroke ();
                    double hs = HANDLE / scale;
                    double[] xs = { pl.ox, pl.ox + inf.width * pl.sx };
                    double[] ys = { pl.oy, pl.oy + inf.height * pl.sy };
                    foreach (double x in xs) foreach (double y in ys) {
                        cr.rectangle (x - hs / 2, y - hs / 2, hs, hs);
                        cr.fill ();
                    }
                    cr.restore ();
                }
            }
            cr.restore ();
        }

        private void draw_cell_selection (Cairo.Context cr, TableItem t) {
            int r1 = int.min (cell_r1, cell_r2), r2 = int.max (cell_r1, cell_r2);
            int c1 = int.min (cell_c1, cell_c2), c2 = int.max (cell_c1, cell_c2);
            double x0 = 0, y0 = 0, x1 = 0, y1 = 0;
            for (int c = 0; c < c1; c++) x0 += t.col_w[c];
            for (int c = 0; c <= c2 && c < t.cols; c++) x1 += t.col_w[c];
            for (int r = 0; r < r1; r++) y0 += t.row_h[r];
            for (int r = 0; r <= r2 && r < t.rows; r++) y1 += t.row_h[r];
            cr.save ();
            renderer.transform (cr, t);
            cr.set_source_rgba (0.2, 0.45, 0.95, 0.18);
            cr.rectangle (x0, y0, x1 - x0, y1 - y0);
            cr.fill_preserve ();
            cr.set_source_rgba (0.2, 0.45, 0.95, 0.9);
            cr.set_line_width (2 / scale);
            cr.stroke ();
            cr.restore ();
        }

        private void draw_ports (Cairo.Context cr, TextFrame t, Rgba c) {
            double s = 9 / scale;
            var st = pub.story (t.story);
            int idx = st.frames.index_of (t.id);
            bool has_prev = idx > 0, has_next = idx >= 0 && idx < st.frames.size - 1;
            var res = master_mode ? cache.master_story (t.story, -1) : cache.story (t.story);
            bool overset = res.overset && !has_next;
            var pin = t.to_page (12 / scale, 0);
            var pout = t.to_page (t.w - 12 / scale, t.h);
            cr.set_line_width (1 / scale);
            foreach (int k in new int[] { 0, 1 }) {
                var p = k == 0 ? pin : pout;
                cr.rectangle (p.x - s / 2, p.y - s / 2, s, s);
                cr.set_source_rgb (1, 1, 1);
                cr.fill_preserve ();
                if (k == 1 && overset) cr.set_source_rgb (0.86, 0.1, 0.1);
                else cr.set_source_rgba (c.r, c.g, c.b, 1);
                cr.stroke ();
                bool linked = k == 0 ? has_prev : has_next;
                if (linked) {
                    cr.move_to (p.x - s / 4, p.y);
                    cr.line_to (p.x + s / 4, p.y);
                    cr.move_to (p.x + s / 8, p.y - s / 5);
                    cr.line_to (p.x + s / 4, p.y);
                    cr.line_to (p.x + s / 8, p.y + s / 5);
                    cr.stroke ();
                } else if (k == 1 && overset) {
                    cr.move_to (p.x - s / 4, p.y);
                    cr.line_to (p.x + s / 4, p.y);
                    cr.move_to (p.x, p.y - s / 4);
                    cr.line_to (p.x, p.y + s / 4);
                    cr.stroke ();
                }
            }
            if (has_next) {
                int next = st.frames[idx + 1];
                var r = pub.find_item (next);
                if (r != null && r.item is TextFrame) {
                    var ns = r.page != null ? slot_for (pub.pages.index_of (r.page)) : null;
                    var cs = active_slot ();
                    if (ns != null && cs != null) {
                        var q = r.item.to_page (12 / scale, 0);
                        cr.set_source_rgba (c.r, c.g, c.b, 0.7);
                        cr.set_dash ({ 3 / scale, 3 / scale }, 0);
                        cr.move_to (pout.x, pout.y);
                        cr.line_to (q.x + ns.x - cs.x, q.y + ns.y - cs.y);
                        cr.stroke ();
                        cr.set_dash (null, 0);
                    }
                }
            }
        }

        private void draw_feedback (Cairo.Context cr) {
            double lw = 1 / scale;
            cr.set_line_width (lw);
            draw_path_feedback (cr);
            draw_wrap_points (cr);
            if (drag == DragKind.RUBBER && drag_started) {
                double x0 = double.min (press_wx, cur_wx), y0 = double.min (press_wy, cur_wy);
                cr.set_source_rgba (0.2, 0.45, 0.95, 0.12);
                cr.rectangle (x0, y0, Math.fabs (cur_wx - press_wx), Math.fabs (cur_wy - press_wy));
                cr.fill_preserve ();
                cr.set_source_rgba (0.2, 0.45, 0.95, 0.8);
                cr.stroke ();
            }
            if (drag == DragKind.CREATE && drag_started) {
                var r = create_rect ();
                var sl = drag_slot ?? active_slot ();
                cr.save ();
                if (sl != null) cr.translate (sl.x, sl.y);
                cr.set_source_rgba (0.2, 0.45, 0.95, 0.9);
                if (tool == Tool.LINE) {
                    cr.move_to (r.x, r.y);
                    cr.line_to (r.x + r.w, r.y + r.h);
                } else if (tool == Tool.ELLIPSE) {
                    cr.save ();
                    cr.translate (r.x + r.w / 2, r.y + r.h / 2);
                    cr.scale (double.max (r.w / 2, 0.1), double.max (r.h / 2, 0.1));
                    cr.arc (0, 0, 1, 0, 2 * Math.PI);
                    cr.restore ();
                } else {
                    cr.rectangle (r.x, r.y, r.w, r.h);
                }
                cr.stroke ();
                cr.restore ();
            }
            if (drag == DragKind.GUIDE && drag_started && drag_slot != null) {
                cr.set_source_rgba (0.1, 0.75, 0.9, 1);
                if (new_guide_vertical) {
                    cr.move_to (cur_wx, wy0);
                    cr.line_to (cur_wx, wy1);
                } else {
                    cr.move_to (wx0, cur_wy);
                    cr.line_to (wx1, cur_wy);
                }
                cr.stroke ();
            }
            if ((drag == DragKind.MOVE || drag == DragKind.RESIZE || drag == DragKind.CREATE) && drag_started && (snap_vx.size > 0 || snap_hy.size > 0)) {
                var sl = drag_slot ?? active_slot ();
                if (sl != null) {
                    cr.save ();
                    cr.translate (sl.x, sl.y);
                    cr.set_source_rgba (0.95, 0.2, 0.55, 0.95);
                    foreach (var x in snap_vx) {
                        cr.move_to (x, -PASTE / 4);
                        cr.line_to (x, pub.settings.height + PASTE / 4);
                    }
                    foreach (var y in snap_hy) {
                        cr.move_to (-PASTE / 4, y);
                        cr.line_to (pub.settings.width + PASTE / 4, y);
                    }
                    cr.stroke ();
                    cr.restore ();
                }
            }
            if (thread_from != null) {
                cr.set_source_rgba (0.2, 0.45, 0.95, 0.8);
                cr.set_dash ({ 3 / scale, 3 / scale }, 0);
                var sl = active_slot ();
                if (sl != null) {
                    var p = thread_from.to_page (thread_from.w - 12 / scale, thread_from.h);
                    cr.move_to (sl.x + p.x, sl.y + p.y);
                    cr.line_to (cur_wx, cur_wy);
                    cr.stroke ();
                }
                cr.set_dash (null, 0);
            }
        }

        public Gee.ArrayList<LineGroup> line_groups () {
            var list = new Gee.ArrayList<LineGroup> ();
            if (edit == null) return list;
            if (edit.table != null) {
                var t = edit.table;
                var cell = t.cells[edit.row][edit.col];
                TableItem view = t;
                double sx = 1;
                double x = 0, y = 0, cw = 0, ch = 0;
                int page = edit.page;
                if (t.flows ()) {
                    bool ov;
                    var chain = TableFlow.chain (pub, t);
                    var parts = TableFlow.assign (pub, t, out ov);
                    for (int i = 0; i < parts.size && i < chain.size; i++) {
                        if (!parts[i].contains (edit.row)) continue;
                        if (edit.row < t.header_rows && i > 0) continue;
                        view = chain[i];
                        double yy = 0;
                        foreach (int r in parts[i]) {
                            if (r == edit.row) break;
                            yy += t.row_h[r];
                        }
                        y = yy;
                        break;
                    }
                    double tw = 0;
                    foreach (var v in t.col_w) tw += v;
                    sx = view != t && tw > 0 ? view.w / tw : 1;
                    var vr = pub.find_item (view.id);
                    if (vr != null && vr.page != null) page = pub.pages.index_of (vr.page);
                } else {
                    for (int r = 0; r < edit.row; r++) y += t.row_h[r];
                }
                for (int c = 0; c < edit.col; c++) x += t.col_w[c] * sx;
                for (int c = edit.col; c < edit.col + cell.col_span && c < t.cols; c++) cw += t.col_w[c] * sx;
                for (int r = edit.row; r < edit.row + cell.row_span && r < t.rows; r++) ch += t.row_h[r];
                var fr = cache.cell (cell.story, double.max (1, cw - 2 * t.cell_inset), 100000, master_mode ? -1 : page);
                double dy = 0;
                if (cell.valign == 1) dy = (ch - 2 * t.cell_inset - fr.content_height) / 2;
                else if (cell.valign == 2) dy = ch - 2 * t.cell_inset - fr.content_height;
                list.add (new LineGroup (view, x + t.cell_inset, y + t.cell_inset + double.max (0, dy), fr.lines, page, edit.left));
                return list;
            }
            var res = master_mode ? cache.master_story (edit.story.id, -1) : cache.story (edit.story.id);
            foreach (var fr in res.frames) {
                if (fr.frame == null) continue;
                var r = pub.find_item (fr.frame.id);
                if (r == null) continue;
                int page = r.page != null ? pub.pages.index_of (r.page) : -1;
                bool left = r.master != null && r.list == r.master.left_items;
                if (master_mode && r.master == null) continue;
                if (!master_mode && r.master != null) continue;
                list.add (new LineGroup (fr.frame, 0, 0, fr.lines, page, left));
            }
            return list;
        }

        private bool caret_line (TextPos p, out LineGroup? group, out LaidLine? line) {
            group = null;
            line = null;
            foreach (var g in line_groups ()) {
                foreach (var l in g.lines) {
                    if (l.is_drop || l.para != p.para) continue;
                    if (p.offset >= l.start && (p.offset < l.end || (p.offset == l.end && (l.para_last || l.end == l.start)))) {
                        group = g;
                        line = l;
                        return true;
                    }
                    if (p.offset == l.end) {
                        group = g;
                        line = l;
                    }
                }
            }
            return line != null;
        }

        private void draw_edit (Cairo.Context cr) {
            if (edit == null || preview) return;
            TextPos a, b;
            edit.ordered (out a, out b);
            var groups = line_groups ();
            if (edit.has_selection ()) {
                cr.set_source_rgba (0.2, 0.45, 0.95, 0.3);
                foreach (var g in groups) {
                    foreach (var l in g.lines) {
                        if (l.is_drop) continue;
                        var ls = TextPos (l.para, l.start);
                        var le = TextPos (l.para, l.end);
                        if (le.compare (a) < 0 || ls.compare (b) > 0) continue;
                        int s0 = ls.compare (a) >= 0 ? l.start : a.offset;
                        int s1 = le.compare (b) <= 0 ? l.end : b.offset;
                        if (a.para < l.para) s0 = l.start;
                        if (b.para > l.para) s1 = l.end;
                        double x0 = l.caret_x (s0), x1 = l.caret_x (s1);
                        if (b.para > l.para && l.para_last) x1 += 4;
                        if (x1 <= x0) continue;
                        cr.save ();
                        var sl = g.page >= 0 ? slot_for (g.page) : slot_for (-1, g.left);
                        if (sl != null) cr.translate (sl.x, sl.y);
                        renderer.transform (cr, g.item);
                        Renderer.text_space (cr, g.item);
                        cr.translate (g.ox, g.oy);
                        cr.rectangle (x0, l.baseline - l.ascent, x1 - x0, l.ascent + l.descent);
                        cr.fill ();
                        cr.restore ();
                    }
                }
            }
            if (hidden_chars) draw_hidden (cr, groups);
            if (!caret_on) return;
            LineGroup? g;
            LaidLine? line;
            if (!caret_line (edit.caret, out g, out line)) return;
            double x = line.caret_x (edit.caret.offset);
            cr.save ();
            var sl = g.page >= 0 ? slot_for (g.page) : slot_for (-1, g.left);
            if (sl != null) cr.translate (sl.x, sl.y);
            renderer.transform (cr, g.item);
            Renderer.text_space (cr, g.item);
            cr.translate (g.ox, g.oy);
            cr.set_source_rgb (0, 0, 0);
            cr.set_line_width (double.max (0.6, 1.2 / scale));
            cr.move_to (x, line.baseline - line.ascent);
            cr.line_to (x, line.baseline + line.descent);
            cr.stroke ();
            cr.restore ();
        }

        private void draw_hidden (Cairo.Context cr, Gee.ArrayList<LineGroup> groups) {
            var layout = new Pango.Layout (TextEngine.context ());
            var fd = new Pango.FontDescription ();
            fd.set_family ("Inter");
            cr.set_source_rgba (0.2, 0.45, 0.95, 0.85);
            foreach (var g in groups) {
                var sl = g.page >= 0 ? slot_for (g.page) : slot_for (-1, g.left);
                foreach (var l in g.lines) {
                    if (l.is_drop) continue;
                    cr.save ();
                    if (sl != null) cr.translate (sl.x, sl.y);
                    renderer.transform (cr, g.item);
                    Renderer.text_space (cr, g.item);
                    cr.translate (g.ox, g.oy);
                    fd.set_absolute_size (double.max (4, l.ascent) * 0.8 * Pango.SCALE);
                    layout.set_font_description (fd);
                    string t = l.layout.get_text ();
                    unowned Pango.LayoutLine pl = l.line ();
                    int end = pl.start_index + pl.length;
                    for (int i = pl.start_index; i < end && i < t.length; i++) {
                        char ch = t[i];
                        if (ch != ' ' && ch != '\t') continue;
                        int xa, xb;
                        pl.index_to_x (i, false, out xa);
                        pl.index_to_x (i, true, out xb);
                        double cx = l.x + l.x_off + (xa + xb) / 2.0 / Pango.SCALE * l.hscale;
                        if (ch == ' ') {
                            cr.arc (cx, l.baseline - l.ascent * 0.3, 0.6, 0, 2 * Math.PI);
                            cr.fill ();
                        } else {
                            layout.set_text ("»", -1);
                            cr.move_to (l.x + l.x_off + xa / (double) Pango.SCALE * l.hscale, l.baseline);
                            Pango.cairo_show_layout_line (cr, layout.get_line_readonly (0));
                        }
                    }
                    if (l.para_last) {
                        layout.set_text ("¶", -1);
                        int w2;
                        pl.index_to_x (end, false, out w2);
                        cr.move_to (l.x + l.x_off + w2 / (double) Pango.SCALE * l.hscale + 1, l.baseline);
                        Pango.cairo_show_layout_line (cr, layout.get_line_readonly (0));
                    }
                    cr.restore ();
                }
            }
        }

        public Rect selection_bounds () {
            if (selection.size == 0) return Rect (0, 0, 0, 0);
            var r = selection[0].bounds ();
            foreach (var it in selection) r = r.union (it.bounds ());
            return r;
        }

        public void select_only (Item? it) {
            selection.clear ();
            cell_r1 = cell_c1 = cell_r2 = cell_c2 = -1;
            if (it != null) selection.add (it);
            content_frame = null;
            selection_changed ();
            queue_draw ();
        }

        public void clear_selection () {
            end_edit ();
            select_only (null);
        }

        public void select_all () {
            if (edit != null) {
                edit.anchor = TextPos (0, 0);
                edit.caret = edit.story.end_pos ();
                selection_changed ();
                queue_draw ();
                return;
            }
            selection.clear ();
            foreach (var it in active_list ()) {
                if (item_locked (it)) continue;
                selection.add (it);
            }
            selection_changed ();
            queue_draw ();
        }

        public bool item_locked (Item it) {
            if (it.locked || it.hidden) return true;
            var l = pub.layer (it.layer);
            return l != null && (l.locked || !l.visible);
        }

        public Item? hit_item (PageSlot sl, double px, double py, bool include_locked = false) {
            var list = renderer.ordered (items_for_slot (sl));
            double tol = 3 / scale;
            for (int i = list.size - 1; i >= 0; i--) {
                var it = list[i];
                if (it.hidden) continue;
                var l = pub.layer (it.layer);
                if (l != null && !l.visible) continue;
                if (!include_locked && l != null && l.locked) continue;
                if (hits (it, px, py, tol)) return it;
            }
            return null;
        }

        private bool hits (Item it, double px, double py, double tol) {
            var s = it as ShapeItem;
            if (s != null && s.shape == ShapeKind.LINE) {
                var pts = s.local_points ();
                var l = it.to_local (px, py);
                double dx = pts[1].x - pts[0].x, dy = pts[1].y - pts[0].y;
                double len2 = dx * dx + dy * dy;
                double t = len2 > 0 ? ((l.x - pts[0].x) * dx + (l.y - pts[0].y) * dy) / len2 : 0;
                t = t.clamp (0, 1);
                double qx = pts[0].x + t * dx - l.x, qy = pts[0].y + t * dy - l.y;
                return Math.sqrt (qx * qx + qy * qy) <= double.max (tol * 2, s.stroke.width);
            }
            return it.hit (px, py, tol);
        }

        public Item? hit_master_item (PageSlot sl, double px, double py) {
            if (sl.page < 0) return null;
            var list = pub.master_items_for (sl.page);
            for (int i = list.size - 1; i >= 0; i--) if (list[i].hit (px, py, 2 / scale) && !list[i].hidden) return list[i];
            return null;
        }

        private int handle_at (Item it, double px, double py) {
            double hs = (HANDLE + 4) / scale;
            var rot = it.to_page (it.w / 2, -22 / scale);
            if (Math.fabs (px - rot.x) < hs && Math.fabs (py - rot.y) < hs) return 100;
            for (int hy = 0; hy < 3; hy++) for (int hx = 0; hx < 3; hx++) {
                if (hx == 1 && hy == 1) continue;
                var p = it.to_page (it.w * hx / 2.0, it.h * hy / 2.0);
                if (Math.fabs (px - p.x) < hs / 1.4 && Math.fabs (py - p.y) < hs / 1.4) return hy * 3 + hx;
            }
            return -1;
        }

        private bool out_port_hit (TextFrame t, double px, double py) {
            var p = t.to_page (t.w - 12 / scale, t.h);
            double s = 8 / scale;
            return Math.fabs (px - p.x) < s && Math.fabs (py - p.y) < s;
        }

        private Guide? guide_hit (PageSlot sl, double px, double py, out Gee.ArrayList<Guide>? owner) {
            owner = null;
            double tol = 4 / scale;
            var own = own_guides (sl);
            foreach (var g in own) {
                if (g.vertical && Math.fabs (px - g.pos) < tol && py > -PASTE / 3 && py < pub.settings.height + PASTE / 3) {
                    owner = own;
                    return g;
                }
                if (!g.vertical && Math.fabs (py - g.pos) < tol && px > -PASTE / 2 && px < pub.settings.width + PASTE / 2) {
                    owner = own;
                    return g;
                }
            }
            return null;
        }

        private void on_pressed (GestureClick g, int n, double x, double y) {
            grab_focus ();
            if (pub == null) return;
            click_count = n;
            uint button = g.get_current_button ();
            double wx, wy;
            to_world (x, y, out wx, out wy);
            var sl = slot_at (wx, wy);
            if (sl == null) return;
            double px = wx - sl.x, py = wy - sl.y;
            var state = g.get_current_event_state ();
            bool shift = (state & Gdk.ModifierType.SHIFT_MASK) != 0;
            bool ctrl = (state & Gdk.ModifierType.CONTROL_MASK) != 0;
            if (button == Gdk.BUTTON_SECONDARY) {
                if (edit == null) {
                    var hit = hit_item (sl, px, py);
                    if (hit != null && !selection.contains (hit)) {
                        set_active_slot (sl);
                        select_only (hit);
                    }
                }
                context_requested (x, y);
                return;
            }
            if (button != Gdk.BUTTON_PRIMARY) return;
            if (show_rulers && (x < RULER || y > get_height () - RULER)) return;
            if (tool == Tool.PEN) {
                if (pen_slot != null && pen_slot != sl) {
                    pen_pts.clear ();
                    pen_handles.clear ();
                }
                pen_slot = sl;
                set_active_slot (sl);
                if (n >= 2) {
                    finish_pen (false);
                    return;
                }
                if (pen_pts.size >= 3) {
                    var first = pen_pts[0];
                    if (Math.fabs (first.x - px) < 6 / scale && Math.fabs (first.y - py) < 6 / scale) {
                        finish_pen (true);
                        return;
                    }
                }
                pen_pts.add (Point (px, py));
                pen_handles.add (Point (0, 0));
                queue_draw ();
                return;
            }
            if (n >= 2 && edit != null) {
                var pos = text_hit (wx, wy);
                if (pos != null) {
                    if (n == 2) {
                        TextPos wa, wb;
                        edit.story.word_bounds (pos, out wa, out wb);
                        edit.anchor = wa;
                        edit.caret = wb;
                    } else {
                        edit.anchor = TextPos (pos.para, 0);
                        edit.caret = TextPos (pos.para, edit.story.paras[pos.para].length ());
                    }
                    selection_changed ();
                    queue_draw ();
                    return;
                }
            }
            if (n == 2 && edit == null && tool == Tool.SELECT) {
                var hit = hit_item (sl, px, py);
                if (hit != null) {
                    set_active_slot (sl);
                    if (hit is TextFrame) {
                        select_only (hit);
                        begin_edit_at ((TextFrame) hit, wx, wy);
                        return;
                    }
                    if (hit is ImageFrame) {
                        select_only (hit);
                        content_frame = (ImageFrame) hit;
                        queue_draw ();
                        return;
                    }
                    if (hit is TableItem) {
                        var t = (TableItem) hit;
                        int r, c;
                        if (cell_at (t, px, py, out r, out c)) begin_cell_edit (t.flows () ? TableFlow.head (pub, t) : t, r, c, wx, wy);
                        return;
                    }
                    if (hit is GroupItem) {
                        item_double_clicked (hit);
                        return;
                    }
                    item_double_clicked (hit);
                    return;
                }
                if (ctrl && shift) {
                    var mi = hit_master_item (sl, px, py);
                    if (mi != null) item_double_clicked (mi);
                }
            }
        }

        public void set_active_slot (PageSlot sl) {
            bool changed = master_mode ? sl.left != sel_left : sl.page != sel_page;
            if (changed) {
                selection.clear ();
                cell_r1 = cell_c1 = cell_r2 = cell_c2 = -1;
            }
            sel_page = sl.page >= 0 ? sl.page : sel_page;
            sel_left = sl.left;
            if (!master_mode && doc.current_page != sl.page && sl.page >= 0) {
                doc.current_page = sl.page;
                page_changed ();
            }
        }

        private bool cell_at (TableItem t, double px, double py, out int row, out int col) {
            row = col = -1;
            var l = t.to_local (px, py);
            if (l.x < 0 || l.y < 0 || l.x > t.w || l.y > t.h) return false;
            if (t.flows ()) {
                TableItem m;
                bool ov;
                var rows = TableFlow.rows_for (pub, t, out m, out ov);
                double tw = 0;
                foreach (var v in m.col_w) tw += v;
                double sx = tw > 0 ? t.w / tw : 1;
                double fx = 0;
                for (int c = 0; c < m.cols; c++) {
                    if (l.x >= fx && l.x <= fx + m.col_w[c] * sx) {
                        col = c;
                        break;
                    }
                    fx += m.col_w[c] * sx;
                }
                double fy = 0;
                foreach (int r in rows) {
                    if (l.y >= fy && l.y <= fy + m.row_h[r]) {
                        row = r;
                        break;
                    }
                    fy += m.row_h[r];
                }
                if (row < 0 || col < 0) return false;
                while (m.cells[row][col].covered && col > 0) col--;
                return true;
            }
            double x = 0;
            for (int c = 0; c < t.cols; c++) {
                if (l.x >= x && l.x <= x + t.col_w[c]) {
                    col = c;
                    break;
                }
                x += t.col_w[c];
            }
            double y = 0;
            for (int r = 0; r < t.rows; r++) {
                if (l.y >= y && l.y <= y + t.row_h[r]) {
                    row = r;
                    break;
                }
                y += t.row_h[r];
            }
            if (row < 0 || col < 0) return false;
            while (t.cells[row][col].covered) {
                bool moved = false;
                for (int r = row; r >= 0 && !moved; r--) for (int c = col; c >= 0; c--) {
                    var cell = t.cells[r][c];
                    if (!cell.covered && r + cell.row_span > row && c + cell.col_span > col) {
                        row = r;
                        col = c;
                        moved = true;
                        break;
                    }
                }
                if (!moved) break;
            }
            return true;
        }

        public TextPos? text_hit (double wx, double wy) {
            if (edit == null) return null;
            var groups = line_groups ();
            LaidLine? best = null;
            double bd = double.MAX;
            bool inside_any = false;
            double best_lx = 0;
            foreach (var g in groups) {
                var sl = g.page >= 0 ? slot_for (g.page) : slot_for (-1, g.left);
                if (sl == null) continue;
                var loc = g.item.to_local (wx - sl.x, wy - sl.y);
                var tloc = Renderer.to_text_space (g.item, loc);
                double lx = tloc.x - g.ox, ly = tloc.y - g.oy;
                bool inside = loc.x >= -4 && loc.y >= -4 && loc.x <= g.item.w + 4 && loc.y <= g.item.h + 4;
                if (!inside && inside_any) continue;
                foreach (var l in g.lines) {
                    if (l.is_drop) continue;
                    double dy = ly < l.baseline - l.ascent ? (l.baseline - l.ascent - ly) : (ly > l.baseline + l.descent ? ly - l.baseline - l.descent : 0);
                    double dx = lx < l.x ? l.x - lx : (lx > l.x + l.width ? lx - l.x - l.width : 0);
                    double d = dy * 4 + dx + (inside ? 0 : 100000);
                    if (d < bd) {
                        bd = d;
                        best = l;
                        best_lx = lx;
                    }
                }
                if (inside) inside_any = true;
            }
            if (best == null) {
                if (groups.size > 0 && inside_any) return edit.story.end_pos ();
                return null;
            }
            return TextPos (best.para, best.hit (best_lx));
        }

        public void begin_edit_at (TextFrame f, double wx, double wy) {
            end_edit ();
            var st = pub.story (f.story);
            edit = new EditState (st);
            edit.frame = f;
            var r = pub.find_item (f.id);
            edit.page = r != null && r.page != null ? pub.pages.index_of (r.page) : -1;
            edit.left = r != null && r.master != null && r.list == r.master.left_items;
            var pos = text_hit (wx, wy);
            edit.collapse (pos ?? st.end_pos ());
            start_blink ();
            attach_im ();
            selection_changed ();
            queue_draw ();
        }

        private void attach_im () {
            key_ctl.set_im_context (im);
            im.set_client_widget (this);
            im.focus_in ();
        }

        public void begin_edit (TextFrame f, bool at_end = true) {
            end_edit ();
            var st = pub.story (f.story);
            edit = new EditState (st);
            edit.frame = f;
            var r = pub.find_item (f.id);
            edit.page = r != null && r.page != null ? pub.pages.index_of (r.page) : -1;
            edit.left = r != null && r.master != null && r.list == r.master.left_items;
            edit.collapse (at_end ? st.end_pos () : TextPos (0, 0));
            if (!at_end) edit.caret = st.end_pos ();
            start_blink ();
            attach_im ();
            selection_changed ();
            queue_draw ();
        }

        public void begin_cell_edit (TableItem t, int r, int c, double wx = double.NAN, double wy = double.NAN) {
            end_edit ();
            var st = t.cells[r][c].story;
            edit = new EditState (st);
            edit.table = t;
            edit.row = r;
            edit.col = c;
            edit.page = master_mode ? -1 : sel_page;
            edit.left = sel_left;
            cell_r1 = cell_r2 = r;
            cell_c1 = cell_c2 = c;
            TextPos? pos = !wx.is_nan () ? text_hit (wx, wy) : null;
            edit.collapse (pos ?? st.end_pos ());
            start_blink ();
            attach_im ();
            selection_changed ();
            queue_draw ();
        }

        public void end_edit () {
            if (edit == null) return;
            edit = null;
            if (blink_id != 0) Source.remove (blink_id);
            blink_id = 0;
            im.reset ();
            im.focus_out ();
            key_ctl.set_im_context (null);
            selection_changed ();
            queue_draw ();
        }

        private void start_blink () {
            caret_on = true;
            if (blink_id != 0) Source.remove (blink_id);
            blink_id = Timeout.add (560, () => {
                caret_on = !caret_on;
                queue_draw ();
                return Source.CONTINUE;
            });
        }

        private void bump_caret () {
            caret_on = true;
            if (blink_id != 0) start_blink ();
        }

        private void on_drag_begin (GestureDrag g, double x, double y) {
            if (pub == null) return;
            uint button = g.get_current_button ();
            drag = DragKind.NONE;
            drag_started = false;
            origs.clear ();
            snap_vx.clear ();
            snap_hy.clear ();
            press_px = x;
            press_py = y;
            to_world (x, y, out press_wx, out press_wy);
            cur_wx = press_wx;
            cur_wy = press_wy;
            var state = g.get_current_event_state ();
            bool shift = (state & Gdk.ModifierType.SHIFT_MASK) != 0;
            bool alt = (state & Gdk.ModifierType.ALT_MASK) != 0;
            if (button == Gdk.BUTTON_MIDDLE || tool == Tool.HAND) {
                drag = DragKind.PAN;
                pan_h0 = _hadj != null ? _hadj.value : 0;
                pan_v0 = _vadj != null ? _vadj.value : 0;
                return;
            }
            if (button != Gdk.BUTTON_PRIMARY) return;
            if (show_rulers && !preview && (x < RULER || y > get_height () - RULER)) {
                if (x < RULER && y > get_height () - RULER) return;
                drag = DragKind.GUIDE;
                new_guide_vertical = x < RULER;
                drag_guide = null;
                drag_slot = active_slot ();
                return;
            }
            var sl = slot_at (press_wx, press_wy);
            if (sl == null) return;
            double px = press_wx - sl.x, py = press_wy - sl.y;
            if (wrap_item != null && begin_wrap_drag (sl, px, py, alt)) return;
            if (tool == Tool.PEN) {
                if (pen_pts.size > 0 && pen_slot == sl) {
                    drag_slot = sl;
                    drag = DragKind.PEN_HANDLE;
                }
                return;
            }
            if (tool == Tool.FREEFORM) {
                set_active_slot (sl);
                drag_slot = sl;
                drag = DragKind.FREEHAND;
                free_pts.clear ();
                free_pts.add (Point (px, py));
                return;
            }
            if (thread_from != null) {
                var target = hit_item (sl, px, py) as TextFrame;
                if (target != null && target != thread_from) {
                    finish_thread (target);
                    drag = DragKind.NONE;
                    return;
                }
                set_active_slot (sl);
                drag_slot = sl;
                drag = DragKind.CREATE;
                return;
            }
            if (edit != null) {
                var pos = text_hit (press_wx, press_wy);
                bool inside = false;
                foreach (var lg in line_groups ()) {
                    var gsl = lg.page >= 0 ? slot_for (lg.page) : slot_for (-1, lg.left);
                    if (gsl != null && lg.item.hit (press_wx - gsl.x, press_wy - gsl.y, 4 / scale)) inside = true;
                }
                if (pos != null && inside) {
                    if (shift) edit.extend (pos);
                    else edit.collapse (pos);
                    edit.pending = null;
                    drag = DragKind.TEXT_SELECT;
                    bump_caret ();
                    selection_changed ();
                    queue_draw ();
                    return;
                }
                if (tool == Tool.TEXT) {
                    var other = hit_item (sl, px, py) as TextFrame;
                    if (other != null) {
                        set_active_slot (sl);
                        select_only (other);
                        begin_edit_at (other, press_wx, press_wy);
                        drag = DragKind.TEXT_SELECT;
                        return;
                    }
                }
                end_edit ();
            }
            if (content_frame != null) {
                var cf = content_frame;
                if (cf.hit (px, py, 4 / scale) || content_handle (cf, px, py) >= 0) {
                    var inf = ImageStore.get_default ().info (pub, cf);
                    if (inf != null) {
                        doc.checkpoint (_("Move Content"));
                        if (cf.fit != FitMode.MANUAL) ImageStore.to_manual (cf, inf);
                        origs.add (new DragOrig (cf));
                        drag = content_handle (cf, px, py) >= 0 ? DragKind.CONTENT_SCALE : DragKind.CONTENT_PAN;
                        drag_slot = sl;
                        return;
                    }
                }
                content_frame = null;
                queue_draw ();
            }
            if (!show_guides || preview) {
            } else if (tool == Tool.SELECT || tool == Tool.CONTENT) {
                Gee.ArrayList<Guide>? owner;
                var gh = guide_hit (sl, px, py, out owner);
                if (gh != null && hit_item_selected_handle (sl, px, py) < 0) {
                    var sel_hit = hit_item (sl, px, py);
                    if (sel_hit == null || !selection.contains (sel_hit)) {
                        drag = DragKind.GUIDE;
                        drag_guide = gh;
                        drag_guide_list = owner;
                        new_guide_vertical = gh.vertical;
                        drag_slot = sl;
                        doc.checkpoint (_("Move Guide"));
                        return;
                    }
                }
            }
            if (tool == Tool.SELECT || tool == Tool.CONTENT) {
                if (selection.size == 1 && sl == active_slot ()) {
                    var it = selection[0];
                    if (it is TextFrame && out_port_hit ((TextFrame) it, px, py)) {
                        thread_from = (TextFrame) it;
                        tool_changed ();
                        queue_draw ();
                        return;
                    }
                    if (!it.locked) {
                        int h = handle_at (it, px, py);
                        if (h == 100) {
                            drag = DragKind.ROTATE;
                            origs.add (new DragOrig (it));
                            drag_slot = sl;
                            return;
                        }
                        if (h >= 0) {
                            drag = DragKind.RESIZE;
                            handle_x = h % 3;
                            handle_y = h / 3;
                            origs.add (new DragOrig (it));
                            drag_slot = sl;
                            return;
                        }
                        if (it is TableItem) {
                            int line;
                            bool col;
                            if (table_border_hit ((TableItem) it, px, py, out line, out col)) {
                                var t = (TableItem) it;
                                drag = col ? DragKind.TABLE_COL : DragKind.TABLE_ROW;
                                table_line = line;
                                table_orig = col ? t.col_w[line] : t.row_h[line];
                                table_next = col ? t.col_w[line + 1] : t.row_h[line + 1];
                                origs.add (new DragOrig (it));
                                drag_slot = sl;
                                return;
                            }
                        }
                    }
                }
                var hit = hit_item (sl, px, py);
                if (hit != null && tool == Tool.CONTENT && hit is ImageFrame) {
                    set_active_slot (sl);
                    select_only (hit);
                    content_frame = (ImageFrame) hit;
                    var inf = ImageStore.get_default ().info (pub, content_frame);
                    if (inf != null) {
                        doc.checkpoint (_("Move Content"));
                        if (content_frame.fit != FitMode.MANUAL) ImageStore.to_manual (content_frame, inf);
                        origs.add (new DragOrig (content_frame));
                        drag = DragKind.CONTENT_PAN;
                        drag_slot = sl;
                    }
                    return;
                }
                if (hit != null) {
                    set_active_slot (sl);
                    if (hit is TableItem && selection.size == 1 && selection[0] == hit && click_count == 1) {
                        int r, c;
                        if (cell_at ((TableItem) hit, px, py, out r, out c)) {
                            if (shift && cell_r1 >= 0) {
                                cell_r2 = r;
                                cell_c2 = c;
                            } else {
                                cell_r1 = cell_r2 = r;
                                cell_c1 = cell_c2 = c;
                            }
                            selection_changed ();
                            queue_draw ();
                        }
                    }
                    if (shift) {
                        if (selection.contains (hit)) selection.remove (hit);
                        else selection.add (hit);
                        selection_changed ();
                    } else if (!selection.contains (hit)) {
                        select_only (hit);
                    }
                    if (item_locked (hit)) return;
                    drag = DragKind.MOVE;
                    drag_copy = alt;
                    drag_slot = sl;
                    foreach (var it in selection) origs.add (new DragOrig (it));
                    orig_bounds = selection_bounds ();
                    queue_draw ();
                    return;
                }
                if (!shift) {
                    set_active_slot (sl);
                    select_only (null);
                }
                drag = DragKind.RUBBER;
                drag_slot = sl;
                return;
            }
            if (tool == Tool.TEXT) {
                var hit = hit_item (sl, px, py) as TextFrame;
                if (hit != null && !item_locked (hit)) {
                    set_active_slot (sl);
                    select_only (hit);
                    begin_edit_at (hit, press_wx, press_wy);
                    drag = DragKind.TEXT_SELECT;
                    return;
                }
            }
            set_active_slot (sl);
            drag_slot = sl;
            drag = DragKind.CREATE;
        }

        private int hit_item_selected_handle (PageSlot sl, double px, double py) {
            if (selection.size != 1 || sl != active_slot ()) return -1;
            return handle_at (selection[0], px, py);
        }

        private bool table_border_hit (TableItem t, double px, double py, out int line, out bool col) {
            line = -1;
            col = false;
            var l = t.to_local (px, py);
            double tol = 3 / scale;
            if (l.y >= 0 && l.y <= t.h) {
                double x = 0;
                for (int c = 0; c < t.cols - 1; c++) {
                    x += t.col_w[c];
                    if (Math.fabs (l.x - x) < tol) {
                        line = c;
                        col = true;
                        return true;
                    }
                }
            }
            if (l.x >= 0 && l.x <= t.w) {
                double y = 0;
                for (int r = 0; r < t.rows - 1; r++) {
                    y += t.row_h[r];
                    if (Math.fabs (l.y - y) < tol) {
                        line = r;
                        col = false;
                        return true;
                    }
                }
            }
            return false;
        }

        private int content_handle (ImageFrame f, double px, double py) {
            var inf = ImageStore.get_default ().info (pub, f);
            if (inf == null) return -1;
            var pl = ImageStore.place (f, inf);
            double hs = (HANDLE + 4) / scale;
            double[] xs = { pl.ox, pl.ox + inf.width * pl.sx };
            double[] ys = { pl.oy, pl.oy + inf.height * pl.sy };
            int k = 0;
            foreach (double y in ys) foreach (double x in xs) {
                var p = f.to_page (x, y);
                if (Math.fabs (px - p.x) < hs && Math.fabs (py - p.y) < hs) return k;
                k++;
            }
            return -1;
        }

        private Rect create_rect () {
            var sl = drag_slot ?? active_slot ();
            double ox = sl != null ? sl.x : 0, oy = sl != null ? sl.y : 0;
            double x0 = press_wx - ox, y0 = press_wy - oy, x1 = cur_wx - ox, y1 = cur_wy - oy;
            if (tool == Tool.LINE) {
                if (shift_down) {
                    double dx = x1 - x0, dy = y1 - y0;
                    double a = Math.round (Math.atan2 (dy, dx) / (Math.PI / 4)) * (Math.PI / 4);
                    double len = Math.sqrt (dx * dx + dy * dy);
                    x1 = x0 + Math.cos (a) * len;
                    y1 = y0 + Math.sin (a) * len;
                }
                return Rect (x0, y0, x1 - x0, y1 - y0);
            }
            if (shift_down) {
                double s = double.max (Math.fabs (x1 - x0), Math.fabs (y1 - y0));
                x1 = x0 + (x1 >= x0 ? s : -s);
                y1 = y0 + (y1 >= y0 ? s : -s);
            }
            return Rect (double.min (x0, x1), double.min (y0, y1), Math.fabs (x1 - x0), Math.fabs (y1 - y0));
        }

        private void on_drag_update (GestureDrag g, double dx, double dy) {
            if (pub == null || drag == DragKind.NONE) return;
            double x = press_px + dx, y = press_py + dy;
            to_world (x, y, out cur_wx, out cur_wy);
            cur_px = x;
            cur_py = y;
            var state = g.get_current_event_state ();
            shift_down = (state & Gdk.ModifierType.SHIFT_MASK) != 0;
            if (!drag_started && Math.fabs (dx) < 3 && Math.fabs (dy) < 3) return;
            if (!drag_started) {
                drag_started = true;
                if (drag == DragKind.MOVE || drag == DragKind.RESIZE || drag == DragKind.ROTATE || drag == DragKind.TABLE_COL || drag == DragKind.TABLE_ROW) {
                    doc.checkpoint (drag == DragKind.MOVE ? (drag_copy ? _("Duplicate") : _("Move")) : (drag == DragKind.ROTATE ? _("Rotate") : _("Resize")));
                    if (drag == DragKind.MOVE && drag_copy) {
                        var copies = new Gee.ArrayList<Item> ();
                        var list = active_list ();
                        foreach (var o in origs) {
                            var c = o.item.clone ();
                            pub.reassign (c);
                            list.add (c);
                            copies.add (c);
                        }
                        origs.clear ();
                        selection.clear ();
                        foreach (var c in copies) {
                            selection.add (c);
                            origs.add (new DragOrig (c));
                        }
                    }
                }
            }
            switch (drag) {
                case DragKind.PAN:
                    auto_fit = false;
                    if (_hadj != null) _hadj.value = (pan_h0 - dx).clamp (0, double.max (0, _hadj.upper - _hadj.page_size));
                    if (_vadj != null) _vadj.value = (pan_v0 - dy).clamp (0, double.max (0, _vadj.upper - _vadj.page_size));
                    break;
                case DragKind.MOVE:
                    do_move ();
                    break;
                case DragKind.RESIZE:
                    do_resize ();
                    break;
                case DragKind.ROTATE:
                    do_rotate ();
                    break;
                case DragKind.CONTENT_PAN:
                    var o = origs[0];
                    var f = (ImageFrame) o.item;
                    var oc = (ImageFrame) o.copy;
                    double a = -f.rotation * Math.PI / 180;
                    double ddx = (cur_wx - press_wx), ddy = (cur_wy - press_wy);
                    f.img_x = oc.img_x + ddx * Math.cos (a) - ddy * Math.sin (a);
                    f.img_y = oc.img_y + ddx * Math.sin (a) + ddy * Math.cos (a);
                    changed_geometry ();
                    break;
                case DragKind.CONTENT_SCALE:
                    var o2 = origs[0];
                    var f2 = (ImageFrame) o2.item;
                    var oc2 = (ImageFrame) o2.copy;
                    var sl2 = drag_slot;
                    var l0 = f2.to_local (press_wx - sl2.x, press_wy - sl2.y);
                    var l1 = f2.to_local (cur_wx - sl2.x, cur_wy - sl2.y);
                    double d0 = Math.sqrt (Math.pow (l0.x - oc2.img_x, 2) + Math.pow (l0.y - oc2.img_y, 2));
                    double d1 = Math.sqrt (Math.pow (l1.x - oc2.img_x, 2) + Math.pow (l1.y - oc2.img_y, 2));
                    if (d0 > 1) f2.img_scale = double.max (0.01, oc2.img_scale * d1 / d0);
                    changed_geometry ();
                    break;
                case DragKind.TABLE_COL:
                case DragKind.TABLE_ROW:
                    var t = (TableItem) origs[0].item;
                    var sl3 = drag_slot;
                    var lp0 = t.to_local (press_wx - sl3.x, press_wy - sl3.y);
                    var lp1 = t.to_local (cur_wx - sl3.x, cur_wy - sl3.y);
                    double d = drag == DragKind.TABLE_COL ? lp1.x - lp0.x : lp1.y - lp0.y;
                    d = d.clamp (-(table_orig - 6), table_next - 6);
                    if (drag == DragKind.TABLE_COL) {
                        t.col_w[table_line] = table_orig + d;
                        t.col_w[table_line + 1] = table_next - d;
                    } else {
                        t.row_h[table_line] = table_orig + d;
                        t.row_h[table_line + 1] = table_next - d;
                    }
                    cache.invalidate ();
                    changed_geometry ();
                    break;
                case DragKind.GUIDE:
                    if (drag_guide != null && drag_slot != null) {
                        double pos = drag_guide.vertical ? cur_wx - drag_slot.x : cur_wy - drag_slot.y;
                        drag_guide.pos = snap_scalar (pos, drag_guide.vertical);
                    }
                    break;
                case DragKind.TEXT_SELECT:
                    var pos = text_hit (cur_wx, cur_wy);
                    if (pos != null && edit != null) {
                        edit.extend (pos);
                        selection_changed ();
                    }
                    break;
                case DragKind.PEN_HANDLE:
                    if (pen_pts.size > 0 && pen_slot != null && pen_handles.size == pen_pts.size) {
                        var lp = pen_pts[pen_pts.size - 1];
                        pen_handles[pen_handles.size - 1] = Point (cur_wx - pen_slot.x - lp.x, cur_wy - pen_slot.y - lp.y);
                        queue_draw ();
                    }
                    break;
                case DragKind.FREEHAND:
                    var fs = drag_slot;
                    if (fs != null) {
                        var np = Point (cur_wx - fs.x, cur_wy - fs.y);
                        var lp = free_pts[free_pts.size - 1];
                        if (Math.hypot (np.x - lp.x, np.y - lp.y) > 1.5 / scale) free_pts.add (np);
                    }
                    queue_draw ();
                    break;
                case DragKind.WRAP_POINT:
                    var ws = drag_slot;
                    if (ws != null && wrap_item != null && wrap_handle >= 0 && wrap_handle < wrap_item.wrap_points.size) {
                        var loc = wrap_item.to_local (cur_wx - ws.x, cur_wy - ws.y);
                        wrap_item.wrap_points[wrap_handle] = Point (loc.x / double.max (1, wrap_item.w), loc.y / double.max (1, wrap_item.h));
                        cache.invalidate ();
                        edited ();
                    }
                    queue_draw ();
                    break;
                case DragKind.CREATE:
                    if (snap) {
                        var sl4 = drag_slot ?? active_slot ();
                        if (sl4 != null) {
                            snap_vx.clear ();
                            snap_hy.clear ();
                            double sx = cur_wx - sl4.x, sy = cur_wy - sl4.y;
                            double tx = snap_value (sx, true, snap_vx, null);
                            double ty = snap_value (sy, false, snap_hy, null);
                            cur_wx = tx + sl4.x;
                            cur_wy = ty + sl4.y;
                        }
                    }
                    break;
                default:
                    break;
            }
            queue_draw ();
        }

        private double snap_scalar (double v, bool vertical) {
            if (!snap) return v;
            var dummy = new Gee.ArrayList<double?> ();
            return snap_value (v, vertical, dummy, null);
        }

        private Gee.ArrayList<double?> targets (bool vertical, Gee.List<Item>? exclude) {
            var list = new Gee.ArrayList<double?> ();
            var sl = drag_slot ?? active_slot ();
            if (sl == null) return list;
            var s = pub.settings;
            if (vertical) {
                list.add (0.0);
                list.add (sl.w);
                list.add (sl.w / 2);
            } else {
                list.add (0.0);
                list.add (sl.h);
                list.add (sl.h / 2);
            }
            Rect m;
            Gee.ArrayList<Rect?> cols;
            if (sl.page >= 0) {
                m = pub.margin_rect (sl.page);
                cols = pub.column_rects (sl.page);
            } else {
                m = pub.margin_rect (sl.left ? 0 : 1);
                cols = pub.column_rects (sl.left ? 0 : 1);
            }
            if (vertical) {
                list.add (m.x);
                list.add (m.x2 ());
                foreach (var c in cols) {
                    list.add (c.x);
                    list.add (c.x2 ());
                }
            } else {
                list.add (m.y);
                list.add (m.y2 ());
            }
            foreach (var g in guides_for (sl)) if (g.vertical == vertical) list.add (g.pos);
            var bl = s.max_bleed ();
            if (bl > 0) {
                list.add (vertical ? -bl : -bl);
                list.add (vertical ? sl.w + bl : sl.h + bl);
            }
            if (smart) {
                foreach (var it in items_for_slot (sl)) {
                    if (exclude != null && exclude.contains (it)) continue;
                    var b = it.bounds ();
                    if (vertical) {
                        list.add (b.x);
                        list.add (b.x + b.w / 2);
                        list.add (b.x2 ());
                    } else {
                        list.add (b.y);
                        list.add (b.y + b.h / 2);
                        list.add (b.y2 ());
                    }
                }
            }
            return list;
        }

        private double snap_value (double v, bool vertical, Gee.ArrayList<double?> hits, Gee.List<Item>? exclude) {
            double tol = 6 / scale;
            double best = v;
            double bd = tol;
            foreach (var t in targets (vertical, exclude)) {
                double d = Math.fabs (t - v);
                if (d < bd) {
                    bd = d;
                    best = t;
                }
            }
            if (best != v || bd < tol) hits.add (best);
            return best;
        }

        private void do_move () {
            double dx = cur_wx - press_wx, dy = cur_wy - press_wy;
            if (shift_down) {
                if (Math.fabs (dx) > Math.fabs (dy)) dy = 0;
                else dx = 0;
            }
            snap_vx.clear ();
            snap_hy.clear ();
            if (snap) {
                var ex = new Gee.ArrayList<Item> ();
                foreach (var o in origs) ex.add (o.item);
                var b = orig_bounds;
                double best_dx = dx, best_dy = dy;
                double tol = 6 / scale;
                double bdx = tol, bdy = tol;
                double sx = 0, sy = 0;
                bool hx = false, hy = false;
                foreach (var t in targets (true, ex)) {
                    foreach (double e in new double[] { b.x, b.x + b.w / 2, b.x2 () }) {
                        double d = Math.fabs (e + dx - t);
                        if (d < bdx) {
                            bdx = d;
                            best_dx = t - e;
                            sx = t;
                            hx = true;
                        }
                    }
                }
                foreach (var t in targets (false, ex)) {
                    foreach (double e in new double[] { b.y, b.y + b.h / 2, b.y2 () }) {
                        double d = Math.fabs (e + dy - t);
                        if (d < bdy) {
                            bdy = d;
                            best_dy = t - e;
                            sy = t;
                            hy = true;
                        }
                    }
                }
                dx = best_dx;
                dy = best_dy;
                if (hx) snap_vx.add (sx);
                if (hy) snap_hy.add (sy);
            }
            foreach (var o in origs) {
                var g = o.item as GroupItem;
                if (g != null) {
                    double ddx = o.copy.x + dx - g.x, ddy = o.copy.y + dy - g.y;
                    g.move_by (ddx, ddy);
                } else {
                    o.item.x = o.copy.x + dx;
                    o.item.y = o.copy.y + dy;
                }
            }
            changed_geometry ();
        }

        private void do_resize () {
            var o = origs[0];
            var it = o.item;
            var c = o.copy;
            var sl = drag_slot;
            var lp = c.to_local (cur_wx - sl.x, cur_wy - sl.y);
            double x0 = 0, y0 = 0, x1 = c.w, y1 = c.h;
            if (handle_x == 0) x0 = lp.x;
            if (handle_x == 2) x1 = lp.x;
            if (handle_y == 0) y0 = lp.y;
            if (handle_y == 2) y1 = lp.y;
            if (snap && c.rotation == 0) {
                snap_vx.clear ();
                snap_hy.clear ();
                var ex = new Gee.ArrayList<Item> ();
                ex.add (it);
                if (handle_x == 0) x0 = snap_value (c.x + x0, true, snap_vx, ex) - c.x;
                if (handle_x == 2) x1 = snap_value (c.x + x1, true, snap_vx, ex) - c.x;
                if (handle_y == 0) y0 = snap_value (c.y + y0, false, snap_hy, ex) - c.y;
                if (handle_y == 2) y1 = snap_value (c.y + y1, false, snap_hy, ex) - c.y;
            }
            bool is_line = it is ShapeItem && ((ShapeItem) it).shape == ShapeKind.LINE;
            double min = is_line ? 0 : 4;
            if (x1 - x0 < min && !is_line) {
                if (handle_x == 0) x0 = x1 - min;
                else x1 = x0 + min;
            }
            if (y1 - y0 < min && !is_line) {
                if (handle_y == 0) y0 = y1 - min;
                else y1 = y0 + min;
            }
            if (shift_down && handle_x != 1 && handle_y != 1 && c.w > 0 && c.h > 0) {
                double ratio = c.w / c.h;
                double nw = x1 - x0, nh = y1 - y0;
                if (nw / ratio > nh) {
                    nh = nw / ratio;
                    if (handle_y == 0) y0 = y1 - nh;
                    else y1 = y0 + nh;
                } else {
                    nw = nh * ratio;
                    if (handle_x == 0) x0 = x1 - nw;
                    else x1 = x0 + nw;
                }
            }
            var p0 = c.to_page (x0, y0);
            var p1 = c.to_page (x1, y1);
            double nw2 = x1 - x0, nh2 = y1 - y0;
            double cx = (p0.x + p1.x) / 2, cy = (p0.y + p1.y) / 2;
            var from = c.box ();
            var to = Rect (cx - nw2 / 2, cy - nh2 / 2, nw2, nh2);
            if (is_line) {
                var s = (ShapeItem) it;
                bool rev = ((ShapeItem) c).line_reverse;
                if (nw2 < 0) rev = !rev;
                if (nh2 < 0) rev = !rev;
                s.line_reverse = rev;
                to = Rect (cx - Math.fabs (nw2) / 2, cy - Math.fabs (nh2) / 2, Math.fabs (nw2), Math.fabs (nh2));
            }
            var g = it as GroupItem;
            if (g != null) {
                g.children.clear ();
                foreach (var ch in ((GroupItem) c).children) g.children.add (ch.clone ());
                g.scale_children (from, to);
            }
            var tb = it as TableItem;
            if (tb != null) {
                var tc = (TableItem) c;
                tb.col_w.clear ();
                tb.row_h.clear ();
                foreach (var v in tc.col_w) tb.col_w.add (v * (from.w > 0 ? to.w / from.w : 1));
                foreach (var v in tc.row_h) tb.row_h.add (tb.flows () ? v : v * (from.h > 0 ? to.h / from.h : 1));
            }
            it.x = to.x;
            it.y = to.y;
            it.w = to.w;
            it.h = to.h;
            changed_geometry ();
        }

        private void do_rotate () {
            var o = origs[0];
            var c = o.copy;
            var sl = drag_slot;
            double cx = c.x + c.w / 2 + sl.x, cy = c.y + c.h / 2 + sl.y;
            double a0 = Math.atan2 (press_wy - cy, press_wx - cx);
            double a1 = Math.atan2 (cur_wy - cy, cur_wx - cx);
            double deg = c.rotation + (a1 - a0) * 180 / Math.PI;
            if (shift_down) deg = Math.round (deg / 15) * 15;
            deg = Math.fmod (deg + 360, 360);
            if (deg > 180) deg -= 360;
            o.item.rotation = Math.round (deg * 10) / 10;
            changed_geometry ();
        }

        private void changed_geometry () {
            cache.invalidate ();
            edited ();
        }

        private void on_drag_end (GestureDrag g, double dx, double dy) {
            if (pub == null) return;
            var kind = drag;
            drag = DragKind.NONE;
            snap_vx.clear ();
            snap_hy.clear ();
            switch (kind) {
                case DragKind.MOVE:
                case DragKind.RESIZE:
                case DragKind.ROTATE:
                case DragKind.TABLE_COL:
                case DragKind.TABLE_ROW:
                    if (drag_started) {
                        doc.touch ();
                        changed_geometry ();
                    }
                    break;
                case DragKind.CONTENT_PAN:
                case DragKind.CONTENT_SCALE:
                    if (drag_started) doc.touch ();
                    else doc.drop_checkpoint ();
                    changed_geometry ();
                    break;
                case DragKind.RUBBER:
                    if (drag_started) {
                        var sl = drag_slot;
                        double x0 = double.min (press_wx, cur_wx) - sl.x, y0 = double.min (press_wy, cur_wy) - sl.y;
                        var r = Rect (x0, y0, Math.fabs (cur_wx - press_wx), Math.fabs (cur_wy - press_wy));
                        foreach (var it in items_for_slot (sl)) {
                            if (item_locked (it)) continue;
                            if (it.bounds ().intersects (r) && !selection.contains (it)) selection.add (it);
                        }
                        selection_changed ();
                    }
                    break;
                case DragKind.CREATE:
                    finish_create ();
                    break;
                case DragKind.FREEHAND:
                    finish_freehand ();
                    break;
                case DragKind.PEN_HANDLE:
                    queue_draw ();
                    break;
                case DragKind.WRAP_POINT:
                    if (drag_started) doc.touch ();
                    else doc.drop_checkpoint ();
                    changed_geometry ();
                    break;
                case DragKind.GUIDE:
                    finish_guide ();
                    break;
                case DragKind.TEXT_SELECT:
                    selection_changed ();
                    break;
                default:
                    break;
            }
            drag_started = false;
            origs.clear ();
            queue_draw ();
        }

        private void finish_guide () {
            if (!drag_started) {
                if (drag_guide != null) doc.drop_checkpoint ();
                drag_guide = null;
                return;
            }
            bool in_ruler = new_guide_vertical ? cur_px < RULER : cur_py > get_height () - RULER;
            if (drag_guide != null) {
                if (in_ruler && drag_guide_list != null) drag_guide_list.remove (drag_guide);
                doc.touch ();
                drag_guide = null;
                edited ();
                return;
            }
            if (in_ruler) return;
            var sl = slot_at (cur_wx, cur_wy) ?? drag_slot;
            if (sl == null) return;
            double pos = new_guide_vertical ? cur_wx - sl.x : cur_wy - sl.y;
            drag_slot = sl;
            pos = snap_scalar (pos, new_guide_vertical);
            var list = own_guides (sl);
            doc.checkpoint (_("Add Guide"));
            list.add (new Guide (new_guide_vertical, Math.round (pos * 100) / 100));
            doc.touch ();
            edited ();
        }

        private void finish_create () {
            var sl = drag_slot ?? active_slot ();
            if (sl == null) return;
            var r = create_rect ();
            bool clicked = !drag_started;
            if (clicked) {
                if (tool == Tool.LINE) return;
                double w = tool == Tool.TEXT || thread_from != null ? (thread_from != null ? thread_from.w : 200) : 100;
                double h = tool == Tool.TEXT || thread_from != null ? (thread_from != null ? thread_from.h : 100) : 100;
                r = Rect (r.x, r.y, w, h);
            } else if (tool != Tool.LINE && (r.w < 2 || r.h < 2)) {
                return;
            }
            var list = items_for_slot (sl);
            var p = pub;
            Item? made = null;
            string label = _("Create");
            doc.checkpoint (label);
            if (thread_from != null) {
                var from = thread_from;
                var t = p.add_text_frame (list, r.x, r.y, r.w, r.h);
                thread_from = null;
                p.link_frames (from, t);
                made = t;
                tool_changed ();
            } else {
                switch (tool) {
                    case Tool.TEXT:
                        var t = p.add_text_frame (list, r.x, r.y, r.w, r.h);
                        made = t;
                        break;
                    case Tool.IMAGE_FRAME:
                        var im = new ImageFrame ();
                        im.id = p.next_id ();
                        im.x = r.x;
                        im.y = r.y;
                        im.w = r.w;
                        im.h = r.h;
                        im.layer = p.default_layer ().id;
                        list.add (im);
                        made = im;
                        break;
                    case Tool.TABLE:
                        var tb = new TableItem (4, 3);
                        tb.id = p.next_id ();
                        tb.x = r.x;
                        tb.y = r.y;
                        tb.w = double.max (r.w, 90);
                        tb.h = double.max (r.h, 60);
                        tb.layer = p.default_layer ().id;
                        tb.init_cells (p);
                        list.add (tb);
                        made = tb;
                        break;
                    default:
                        ShapeKind k = ShapeKind.RECT;
                        if (tool == Tool.ELLIPSE) k = ShapeKind.ELLIPSE;
                        else if (tool == Tool.POLYGON) k = ShapeKind.POLYGON;
                        else if (tool == Tool.STAR) k = ShapeKind.STAR;
                        else if (tool == Tool.LINE) k = ShapeKind.LINE;
                        var s = new ShapeItem (k);
                        s.id = p.next_id ();
                        s.layer = p.default_layer ().id;
                        if (k == ShapeKind.LINE) {
                            s.x = double.min (r.x, r.x + r.w);
                            s.y = double.min (r.y, r.y + r.h);
                            s.w = Math.fabs (r.w);
                            s.h = Math.fabs (r.h);
                            s.line_reverse = (r.w < 0) != (r.h < 0);
                            s.stroke = new Stroke.with (ColorRef.BLACK, 1);
                        } else {
                            s.x = r.x;
                            s.y = r.y;
                            s.w = r.w;
                            s.h = r.h;
                            s.stroke = new Stroke.with (ColorRef.BLACK, 1);
                            s.fill = new Fill.solid (ColorRef.swatch ("Cyan", 20));
                        }
                        if (k == ShapeKind.STAR) s.sides = 5;
                        list.add (s);
                        made = s;
                        break;
                }
            }
            doc.touch ();
            cache.invalidate ();
            select_only (made);
            if (made is TextFrame && tool == Tool.TEXT) begin_edit ((TextFrame) made);
            edited ();
        }

        private void draw_path_feedback (Cairo.Context cr) {
            Gee.ArrayList<Point?>? pts = null;
            PageSlot? sl = null;
            if (drag == DragKind.FREEHAND && free_pts.size > 1) {
                pts = free_pts;
                sl = drag_slot;
            } else if (tool == Tool.PEN && pen_pts.size > 0) {
                pts = pen_pts;
                sl = pen_slot;
            }
            if (pts == null || sl == null) return;
            cr.save ();
            cr.translate (sl.x, sl.y);
            cr.set_source_rgba (0.2, 0.45, 0.95, 0.95);
            cr.set_line_width (1.5 / scale);
            cr.move_to (pts[0].x, pts[0].y);
            bool pen = tool == Tool.PEN && pts == pen_pts && pen_handles.size == pts.size;
            for (int i = 1; i < pts.size; i++) {
                if (pen) {
                    var ha = pen_handles[i - 1], hb = pen_handles[i];
                    cr.curve_to (pts[i - 1].x + ha.x, pts[i - 1].y + ha.y, pts[i].x - hb.x, pts[i].y - hb.y, pts[i].x, pts[i].y);
                } else {
                    cr.line_to (pts[i].x, pts[i].y);
                }
            }
            if (tool == Tool.PEN && drag != DragKind.PEN_HANDLE) {
                double cx = cur_wx - sl.x, cy = cur_wy - sl.y;
                cr.line_to (cx, cy);
            }
            cr.stroke ();
            if (pen) {
                cr.set_line_width (1 / scale);
                for (int i = 0; i < pts.size; i++) {
                    var hd = pen_handles[i];
                    if (Math.fabs (hd.x) < 0.5 && Math.fabs (hd.y) < 0.5) continue;
                    cr.move_to (pts[i].x - hd.x, pts[i].y - hd.y);
                    cr.line_to (pts[i].x + hd.x, pts[i].y + hd.y);
                    cr.stroke ();
                    cr.arc (pts[i].x + hd.x, pts[i].y + hd.y, 3 / scale, 0, 2 * Math.PI);
                    cr.fill ();
                    cr.arc (pts[i].x - hd.x, pts[i].y - hd.y, 3 / scale, 0, 2 * Math.PI);
                    cr.fill ();
                }
            }
            if (tool == Tool.PEN) {
                foreach (var p in pts) {
                    cr.rectangle (p.x - 3 / scale, p.y - 3 / scale, 6 / scale, 6 / scale);
                    cr.fill ();
                }
            }
            cr.restore ();
        }

        private void draw_wrap_points (Cairo.Context cr) {
            if (wrap_item == null || wrap_item.wrap_points.size < 3) return;
            var r = pub.find_item (wrap_item.id);
            if (r == null) return;
            PageSlot? sl = r.page != null ? slot_for (pub.pages.index_of (r.page)) : active_slot ();
            if (sl == null) return;
            cr.save ();
            cr.translate (sl.x, sl.y);
            var pts = wrap_item.wrap_outline ();
            cr.set_source_rgba (0.85, 0.3, 0.1, 0.95);
            cr.set_line_width (1 / scale);
            cr.set_dash ({ 4 / scale, 3 / scale }, 0);
            cr.move_to (pts[0].x, pts[0].y);
            for (int i = 1; i < pts.size; i++) cr.line_to (pts[i].x, pts[i].y);
            cr.close_path ();
            cr.stroke ();
            cr.set_dash (null, 0);
            foreach (var p in pts) {
                cr.rectangle (p.x - 3.5 / scale, p.y - 3.5 / scale, 7 / scale, 7 / scale);
                cr.set_source_rgb (1, 1, 1);
                cr.fill_preserve ();
                cr.set_source_rgba (0.85, 0.3, 0.1, 1);
                cr.stroke ();
            }
            cr.restore ();
        }

        public void start_wrap_edit (Item it) {
            if (it.wrap_points.size < 3) {
                it.wrap_points.clear ();
                var outline = it.outline ();
                if (it is ImageFrame && !it.shape_ellipse) {
                    double[] u = { 0, 0.5, 1, 1, 1, 0.5, 0, 0 };
                    double[] v = { 0, 0, 0, 0.5, 1, 1, 1, 0.5 };
                    for (int i = 0; i < u.length; i++) it.wrap_points.add (Point (u[i], v[i]));
                } else {
                    int step = int.max (1, outline.size / 24);
                    for (int i = 0; i < outline.size; i += step) {
                        var l = it.to_local (outline[i].x, outline[i].y);
                        it.wrap_points.add (Point (l.x / double.max (1, it.w), l.y / double.max (1, it.h)));
                    }
                }
                if (!it.wrap.wraps () || it.wrap == WrapMode.BOUNDING_BOX || it.wrap == WrapMode.JUMP) it.wrap = WrapMode.CONTOUR;
            }
            wrap_item = it;
            cache.invalidate ();
            queue_draw ();
        }

        public void stop_wrap_edit () {
            wrap_item = null;
            wrap_handle = -1;
            queue_draw ();
        }

        private bool begin_wrap_drag (PageSlot sl, double px, double py, bool alt) {
            var it = wrap_item;
            if (it.wrap_points.size < 3) return false;
            var pts = it.wrap_outline ();
            double tol = 6 / scale;
            for (int i = 0; i < pts.size; i++) {
                if (Math.fabs (pts[i].x - px) <= tol && Math.fabs (pts[i].y - py) <= tol) {
                    doc.checkpoint (_("Edit Wrap Points"));
                    if (alt && it.wrap_points.size > 3) {
                        it.wrap_points.remove_at (i);
                        doc.touch ();
                        changed_geometry ();
                        queue_draw ();
                        drag = DragKind.NONE;
                        return true;
                    }
                    wrap_handle = i;
                    drag_slot = sl;
                    drag = DragKind.WRAP_POINT;
                    return true;
                }
            }
            for (int i = 0; i < pts.size; i++) {
                var a = pts[i];
                var b = pts[(i + 1) % pts.size];
                double dx = b.x - a.x, dy = b.y - a.y;
                double len2 = dx * dx + dy * dy;
                if (len2 < 1e-6) continue;
                double t = ((px - a.x) * dx + (py - a.y) * dy) / len2;
                if (t < 0 || t > 1) continue;
                double qx = a.x + t * dx, qy = a.y + t * dy;
                if (Math.hypot (qx - px, qy - py) <= tol) {
                    doc.checkpoint (_("Add Wrap Point"));
                    var l = it.to_local (px, py);
                    it.wrap_points.insert (i + 1, Point (l.x / double.max (1, it.w), l.y / double.max (1, it.h)));
                    wrap_handle = i + 1;
                    drag_slot = sl;
                    drag = DragKind.WRAP_POINT;
                    changed_geometry ();
                    return true;
                }
            }
            return false;
        }

        private static void simplify (Gee.ArrayList<Point?> pts, int a, int b, double eps, Gee.ArrayList<int> keep) {
            if (b <= a + 1) return;
            double dx = pts[b].x - pts[a].x, dy = pts[b].y - pts[a].y;
            double len = Math.hypot (dx, dy);
            int best = -1;
            double bd = -1;
            for (int i = a + 1; i < b; i++) {
                double d = len < 1e-9 ? Math.hypot (pts[i].x - pts[a].x, pts[i].y - pts[a].y) : Math.fabs (dy * pts[i].x - dx * pts[i].y + pts[b].x * pts[a].y - pts[b].y * pts[a].x) / len;
                if (d > bd) {
                    bd = d;
                    best = i;
                }
            }
            if (bd > eps) {
                keep.add (best);
                simplify (pts, a, best, eps, keep);
                simplify (pts, best, b, eps, keep);
            }
        }

        private Item? make_path (PageSlot sl, Gee.ArrayList<Point?> raw, bool closed, bool smooth_it) {
            var pts = new Gee.ArrayList<Point?> ();
            if (smooth_it && raw.size > 2) {
                var keep = new Gee.ArrayList<int> ();
                keep.add (0);
                keep.add (raw.size - 1);
                simplify (raw, 0, raw.size - 1, 0.8, keep);
                keep.sort ((x, y) => x - y);
                foreach (int k in keep) pts.add (raw[k]);
            } else {
                pts.add_all (raw);
            }
            if (pts.size < 2) return null;
            double minx = double.MAX, miny = double.MAX, maxx = -double.MAX, maxy = -double.MAX;
            foreach (var p in pts) {
                minx = double.min (minx, p.x);
                miny = double.min (miny, p.y);
                maxx = double.max (maxx, p.x);
                maxy = double.max (maxy, p.y);
            }
            double w = double.max (1, maxx - minx), h = double.max (1, maxy - miny);
            var s = new ShapeItem (ShapeKind.PATH);
            s.id = pub.next_id ();
            s.layer = pub.default_layer ().id;
            s.x = minx;
            s.y = miny;
            s.w = w;
            s.h = h;
            s.closed = closed;
            foreach (var p in pts) s.points.add (Point ((p.x - minx) / w, (p.y - miny) / h));
            if (smooth_it && s.points.size >= 3) s.path_d = SvgPath.smooth (s.points, closed);
            s.stroke = new Stroke.with (ColorRef.BLACK, 1.5);
            s.stroke.join = 1;
            s.stroke.cap = 1;
            if (closed) s.fill = new Fill.solid (ColorRef.swatch ("Cyan", 20));
            doc.checkpoint (_("Draw"));
            items_for_slot (sl).add (s);
            doc.touch ();
            cache.invalidate ();
            select_only (s);
            edited ();
            return s;
        }

        private void finish_freehand () {
            var sl = drag_slot;
            if (sl == null || free_pts.size < 2) {
                free_pts.clear ();
                queue_draw ();
                return;
            }
            var first = free_pts[0];
            var last = free_pts[free_pts.size - 1];
            bool closed = free_pts.size > 8 && Math.hypot (first.x - last.x, first.y - last.y) < 10 / scale;
            make_path (sl, free_pts, closed, true);
            free_pts.clear ();
            queue_draw ();
        }

        public void finish_pen (bool closed) {
            var sl = pen_slot;
            bool curved = false;
            foreach (var hd in pen_handles) if (Math.fabs (hd.x) > 0.5 || Math.fabs (hd.y) > 0.5) curved = true;
            if (sl != null && pen_pts.size >= 2) {
                var made = make_path (sl, pen_pts, closed, false) as ShapeItem;
                if (made != null && curved) {
                    var all = new Gee.ArrayList<Point?> ();
                    for (int i = 0; i < pen_pts.size; i++) {
                        var hd = i < pen_handles.size ? pen_handles[i] : Point (0, 0);
                        all.add (Point (pen_pts[i].x + hd.x, pen_pts[i].y + hd.y));
                        all.add (Point (pen_pts[i].x - hd.x, pen_pts[i].y - hd.y));
                        all.add (pen_pts[i]);
                    }
                    double minx = double.MAX, miny = double.MAX, maxx = -double.MAX, maxy = -double.MAX;
                    foreach (var q in all) {
                        minx = double.min (minx, q.x);
                        miny = double.min (miny, q.y);
                        maxx = double.max (maxx, q.x);
                        maxy = double.max (maxy, q.y);
                    }
                    double w = double.max (1, maxx - minx), h = double.max (1, maxy - miny);
                    made.x = minx;
                    made.y = miny;
                    made.w = w;
                    made.h = h;
                    made.path_d = SvgPath.bezier_d (pen_pts, pen_handles, closed, minx, miny, w, h);
                    cache.invalidate ();
                    queue_draw ();
                }
            }
            pen_pts.clear ();
            pen_handles.clear ();
            pen_slot = null;
            queue_draw ();
        }

        public void finish_thread (TextFrame target) {
            if (thread_from == null) return;
            doc.checkpoint (_("Thread Frames"));
            pub.link_frames (thread_from, target);
            thread_from = null;
            doc.touch ();
            cache.invalidate ();
            select_only (target);
            tool_changed ();
            edited ();
            text_changed ();
        }

        private void on_motion (double x, double y) {
            cur_px = x;
            cur_py = y;
            if (pub == null) return;
            to_world (x, y, out cur_wx, out cur_wy);
            if (separations) {
                var sl = slot_at (cur_wx, cur_wy);
                if (sl != null && sl.page >= 0) page_pointer (sl.page, cur_wx - sl.x, cur_wy - sl.y);
            }
            if (thread_from != null) queue_draw ();
            else if (show_rulers) queue_draw ();
            update_cursor ();
        }

        private void update_cursor () {
            string name = "default";
            if (show_rulers && (cur_px < RULER || cur_py > get_height () - RULER)) name = cur_px < RULER ? "col-resize" : "row-resize";
            else if (thread_from != null) name = "copy";
            else if (tool == Tool.HAND) name = "grab";
            else if (tool == Tool.TEXT) name = "text";
            else if (tool != Tool.SELECT && tool != Tool.CONTENT) name = "crosshair";
            else if (edit != null) name = "text";
            else {
                var sl = slot_at (cur_wx, cur_wy);
                if (sl != null) {
                    double px = cur_wx - sl.x, py = cur_wy - sl.y;
                    if (selection.size == 1 && sl == active_slot ()) {
                        int h = handle_at (selection[0], px, py);
                        if (h == 100) name = "grab";
                        else if (h == 0 || h == 8) name = "nwse-resize";
                        else if (h == 2 || h == 6) name = "nesw-resize";
                        else if (h == 1 || h == 7) name = "ns-resize";
                        else if (h == 3 || h == 5) name = "ew-resize";
                        else if (selection[0] is TextFrame && out_port_hit ((TextFrame) selection[0], px, py)) name = "pointer";
                    }
                    if (name == "default" && show_guides) {
                        Gee.ArrayList<Guide>? owner;
                        var gh = guide_hit (sl, px, py, out owner);
                        if (gh != null) name = gh.vertical ? "col-resize" : "row-resize";
                    }
                    if (name == "default" && hit_item (sl, px, py) != null) name = "move";
                }
            }
            set_cursor_from_name (name);
        }

        public void set_tool (Tool t) {
            if (t != Tool.TEXT && t != Tool.SELECT) end_edit ();
            if (tool == Tool.PEN && t != Tool.PEN && pen_pts.size >= 2) finish_pen (false);
            pen_pts.clear ();
            pen_handles.clear ();
            tool = t;
            thread_from = null;
            content_frame = (t == Tool.CONTENT && selection.size == 1 && (selection[0] is ImageFrame)) ? (ImageFrame) selection[0] : null;
            tool_changed ();
            update_cursor ();
            queue_draw ();
        }

        private void scale_content (double factor) {
            var f = content_frame;
            var inf = ImageStore.get_default ().info (pub, f);
            if (inf == null) return;
            doc.checkpoint (_("Scale Content"), "content-scale");
            if (f.fit != FitMode.MANUAL) ImageStore.to_manual (f, inf);
            var pl = ImageStore.place (f, inf);
            double cx = f.w / 2, cy = f.h / 2;
            double ix = (cx - pl.ox) / pl.sx, iy = (cy - pl.oy) / pl.sy;
            f.img_scale *= factor;
            var pl2 = ImageStore.place (f, inf);
            f.img_x = cx - ix * pl2.sx;
            f.img_y = cy - iy * pl2.sy;
            doc.touch ();
            changed_geometry ();
            queue_draw ();
        }

        private bool on_key (EventControllerKey c, uint keyval, uint keycode, Gdk.ModifierType state) {
            if (pub == null) return false;
            bool ctrl = (state & Gdk.ModifierType.CONTROL_MASK) != 0;
            bool shift = (state & Gdk.ModifierType.SHIFT_MASK) != 0;
            bool alt = (state & Gdk.ModifierType.ALT_MASK) != 0;
            shift_down = shift;
            if (edit != null) return edit_key (keyval, ctrl, shift, alt);
            switch (keyval) {
                case Gdk.Key.Escape:
                    if (tool == Tool.PEN && pen_pts.size > 0) {
                        finish_pen (false);
                        return true;
                    }
                    if (wrap_item != null) {
                        stop_wrap_edit ();
                        return true;
                    }
                    if (thread_from != null) {
                        thread_from = null;
                        tool_changed ();
                    } else if (content_frame != null) {
                        content_frame = null;
                    } else if (tool != Tool.SELECT) {
                        set_tool (Tool.SELECT);
                    } else {
                        select_only (null);
                    }
                    queue_draw ();
                    return true;
                case Gdk.Key.Delete:
                case Gdk.Key.BackSpace:
                    if (selection.size == 0) return false;
                    activate_action_variant ("win.delete", null);
                    return true;
                case Gdk.Key.Return:
                case Gdk.Key.KP_Enter:
                    if (tool == Tool.PEN && pen_pts.size >= 2) {
                        finish_pen (false);
                        return true;
                    }
                    if (selection.size == 1 && selection[0] is TextFrame) {
                        begin_edit ((TextFrame) selection[0]);
                        return true;
                    }
                    if (selection.size == 1 && selection[0] is ImageFrame) {
                        content_frame = (ImageFrame) selection[0];
                        queue_draw ();
                        return true;
                    }
                    return false;
                case Gdk.Key.Left:
                case Gdk.Key.Right:
                case Gdk.Key.Up:
                case Gdk.Key.Down:
                    if (selection.size == 0) return false;
                    double step = shift ? 10 : 1;
                    double dx = keyval == Gdk.Key.Left ? -step : (keyval == Gdk.Key.Right ? step : 0);
                    double dy = keyval == Gdk.Key.Up ? -step : (keyval == Gdk.Key.Down ? step : 0);
                    doc.checkpoint (_("Nudge"), "nudge");
                    foreach (var it in selection) {
                        if (item_locked (it)) continue;
                        if (content_frame == it) {
                            var inf = ImageStore.get_default ().info (pub, content_frame);
                            if (inf != null && content_frame.fit != FitMode.MANUAL) ImageStore.to_manual (content_frame, inf);
                            content_frame.img_x += dx;
                            content_frame.img_y += dy;
                            continue;
                        }
                        var g = it as GroupItem;
                        if (g != null) g.move_by (dx, dy);
                        else {
                            it.x += dx;
                            it.y += dy;
                        }
                    }
                    doc.touch ();
                    changed_geometry ();
                    queue_draw ();
                    return true;
                case Gdk.Key.Page_Down:
                    activate_action_variant ("win.next-page", null);
                    return true;
                case Gdk.Key.Page_Up:
                    activate_action_variant ("win.prev-page", null);
                    return true;
                default:
                    break;
            }
            if (ctrl || alt) return false;
            switch (keyval) {
                case Gdk.Key.v: set_tool (Tool.SELECT); return true;
                case Gdk.Key.a: set_tool (Tool.CONTENT); return true;
                case Gdk.Key.t: set_tool (Tool.TEXT); return true;
                case Gdk.Key.f: set_tool (Tool.IMAGE_FRAME); return true;
                case Gdk.Key.m: set_tool (Tool.RECT); return true;
                case Gdk.Key.l: set_tool (Tool.ELLIPSE); return true;
                case Gdk.Key.p: set_tool (Tool.POLYGON); return true;
                case Gdk.Key.s: set_tool (Tool.STAR); return true;
                case Gdk.Key.backslash: set_tool (Tool.LINE); return true;
                case Gdk.Key.b: set_tool (Tool.TABLE); return true;
                case Gdk.Key.h: set_tool (Tool.HAND); return true;
                case Gdk.Key.w: preview = !preview; queue_draw (); tool_changed (); return true;
                default: return false;
            }
        }

        public void text_edited (string label = "", string key = "") {
            if (edit == null) return;
            cache.invalidate_story (edit.story.id);
            if (edit.table != null) cache.invalidate ();
            fit_auto_height ();
            bump_caret ();
            text_changed ();
            queue_draw ();
        }

        public void fit_auto_height () {
            if (edit == null || edit.frame == null) return;
            bool any = false;
            foreach (var f in pub.thread_frames (edit.story.id)) if (f.auto_height) any = true;
            if (!any) return;
            var res = master_mode ? cache.master_story (edit.story.id, -1) : cache.story (edit.story.id);
            foreach (var fr in res.frames) {
                var f = fr.frame;
                if (f == null || !f.auto_height) continue;
                double h = double.max (12, fr.content_height + f.inset_bottom);
                if (Math.fabs (f.h - h) > 0.5) f.h = h;
            }
            cache.invalidate_story (edit.story.id);
        }

        private Run? typing_template () {
            if (edit.pending != null) return edit.pending;
            return null;
        }

        public void insert_text (string text) {
            if (edit == null || text == "") return;
            doc.checkpoint (_("Typing"), "typing:%d".printf (edit.story.id));
            if (edit.has_selection ()) {
                TextPos a, b;
                edit.ordered (out a, out b);
                var tmpl = edit.story.format_at (TextPos (a.para, a.offset + 1)).clone ();
                edit.story.delete_range (a, b);
                edit.collapse (a);
                if (edit.pending == null) edit.pending = tmpl;
            }
            var pos = edit.story.insert_text (edit.caret, text, typing_template ());
            edit.collapse (pos);
            doc.touch ();
            text_edited ();
        }

        public Run? insert_footnote () {
            if (edit == null) return null;
            doc.checkpoint (_("Insert Footnote"));
            if (edit.has_selection ()) {
                TextPos a, b;
                edit.ordered (out a, out b);
                edit.story.delete_range (a, b);
                edit.collapse (a);
            }
            var run = Footnotes.make_run (doc.pub, "");
            var pos = edit.story.insert_run (edit.caret, run);
            edit.collapse (pos);
            doc.touch ();
            text_edited ();
            return run;
        }

        public void insert_field (string field) {
            if (edit == null) return;
            doc.checkpoint (_("Insert Field"));
            if (edit.has_selection ()) {
                TextPos a, b;
                edit.ordered (out a, out b);
                edit.story.delete_range (a, b);
                edit.collapse (a);
            }
            var pos = edit.story.insert_field (edit.caret, field);
            edit.collapse (pos);
            doc.touch ();
            text_edited ();
        }

        private void on_commit (string text) {
            if (edit == null) return;
            if (text == "\n" || text == "\r") return;
            insert_text (text);
        }

        private void delete_selection_or (bool forward, bool word) {
            doc.checkpoint (_("Delete Text"), "delete:%d".printf (edit.story.id));
            if (edit.has_selection ()) {
                TextPos a, b;
                edit.ordered (out a, out b);
                edit.story.delete_range (a, b);
                edit.collapse (a);
            } else {
                var s = edit.story;
                TextPos other = forward ? TextNav.right (s, edit.caret, word) : TextNav.left (s, edit.caret, word);
                if (other.equals (edit.caret)) {
                    doc.drop_checkpoint ();
                    return;
                }
                TextPos a = forward ? edit.caret : other, b = forward ? other : edit.caret;
                s.delete_range (a, b);
                edit.collapse (a);
            }
            doc.touch ();
            text_edited ();
        }

        private bool move_vertical (int dir, bool shift) {
            LineGroup? g;
            LaidLine? line;
            if (!caret_line (edit.caret, out g, out line)) return false;
            double x = edit.goal_x.is_nan () ? line.caret_x (edit.caret.offset) : edit.goal_x;
            var groups = line_groups ();
            var all = new Gee.ArrayList<LaidLine> ();
            var owners = new Gee.ArrayList<LineGroup> ();
            foreach (var gg in groups) foreach (var l in gg.lines) {
                if (l.is_drop) continue;
                all.add (l);
                owners.add (gg);
            }
            int idx = all.index_of (line);
            if (idx < 0) return false;
            LaidLine? target = null;
            if (dir > 0) {
                double best = double.MAX;
                for (int i = 0; i < all.size; i++) {
                    var l = all[i];
                    if (owners[i] != g) continue;
                    if (l.column == line.column && l.baseline > line.baseline + 0.5) {
                        double d = (l.baseline - line.baseline) * 10 + Math.fabs (l.x - line.x);
                        if (d < best) {
                            best = d;
                            target = l;
                        }
                    }
                }
                if (target == null) {
                    for (int i = idx + 1; i < all.size; i++) if (all[i].baseline != line.baseline || owners[i] != g) {
                        target = all[i];
                        break;
                    }
                }
            } else {
                double best = double.MAX;
                for (int i = 0; i < all.size; i++) {
                    var l = all[i];
                    if (owners[i] != g) continue;
                    if (l.column == line.column && l.baseline < line.baseline - 0.5) {
                        double d = (line.baseline - l.baseline) * 10 + Math.fabs (l.x - line.x);
                        if (d < best) {
                            best = d;
                            target = l;
                        }
                    }
                }
                if (target == null) {
                    for (int i = idx - 1; i >= 0; i--) if (all[i].baseline != line.baseline || owners[i] != g) {
                        target = all[i];
                        break;
                    }
                }
            }
            var np = target != null ? TextPos (target.para, target.hit (x)) : (dir > 0 ? edit.story.end_pos () : TextPos (0, 0));
            if (shift) edit.caret = np;
            else {
                edit.caret = np;
                edit.anchor = np;
            }
            edit.goal_x = x;
            return true;
        }

        private void line_edge (bool end, bool shift) {
            LineGroup? g;
            LaidLine? line;
            TextPos np;
            if (caret_line (edit.caret, out g, out line)) np = TextPos (line.para, end ? (line.para_last ? line.end : int.max (line.start, line.end - (line.end > line.start ? 0 : 0))) : line.start);
            else np = TextPos (edit.caret.para, end ? edit.story.paras[edit.caret.para].length () : 0);
            if (end && !line.para_last && np.offset > line.start) {
                string t = edit.story.paras[np.para].text ();
                int bi = t.index_of_nth_char (np.offset - 1);
                if (bi < t.length && t.get_char (bi) == ' ') np = TextPos (np.para, np.offset - 1);
            }
            if (shift) edit.extend (np);
            else edit.collapse (np);
        }

        private bool edit_key (uint keyval, bool ctrl, bool shift, bool alt) {
            var s = edit.story;
            switch (keyval) {
                case Gdk.Key.Escape:
                    var f = edit.frame;
                    var t = edit.table;
                    end_edit ();
                    select_only (f != null ? (Item) f : (Item) t);
                    return true;
                case Gdk.Key.Left:
                    if (edit.has_selection () && !shift) edit.collapse (edit.caret.compare (edit.anchor) < 0 ? edit.caret : edit.anchor);
                    else if (shift) edit.extend (TextNav.left (s, edit.caret, ctrl));
                    else edit.collapse (TextNav.left (s, edit.caret, ctrl));
                    break;
                case Gdk.Key.Right:
                    if (edit.has_selection () && !shift) edit.collapse (edit.caret.compare (edit.anchor) > 0 ? edit.caret : edit.anchor);
                    else if (shift) edit.extend (TextNav.right (s, edit.caret, ctrl));
                    else edit.collapse (TextNav.right (s, edit.caret, ctrl));
                    break;
                case Gdk.Key.Up:
                    if (ctrl) {
                        var np = TextPos (edit.caret.offset == 0 && edit.caret.para > 0 ? edit.caret.para - 1 : edit.caret.para, 0);
                        if (shift) edit.extend (np);
                        else edit.collapse (np);
                    } else move_vertical (-1, shift);
                    break;
                case Gdk.Key.Down:
                    if (ctrl) {
                        int p = int.min (edit.caret.para + 1, s.paras.size - 1);
                        var np = p == edit.caret.para ? TextPos (p, s.paras[p].length ()) : TextPos (p, 0);
                        if (shift) edit.extend (np);
                        else edit.collapse (np);
                    } else move_vertical (1, shift);
                    break;
                case Gdk.Key.Home:
                    if (ctrl) {
                        if (shift) edit.extend (TextPos (0, 0));
                        else edit.collapse (TextPos (0, 0));
                    } else line_edge (false, shift);
                    break;
                case Gdk.Key.End:
                    if (ctrl) {
                        if (shift) edit.extend (s.end_pos ());
                        else edit.collapse (s.end_pos ());
                    } else line_edge (true, shift);
                    break;
                case Gdk.Key.BackSpace:
                    delete_selection_or (false, ctrl);
                    return true;
                case Gdk.Key.Delete:
                case Gdk.Key.KP_Delete:
                    delete_selection_or (true, ctrl);
                    return true;
                case Gdk.Key.Return:
                case Gdk.Key.KP_Enter:
                    if (shift) {
                        insert_text ("\u2028");
                        return true;
                    }
                    new_paragraph ();
                    return true;
                case Gdk.Key.Tab:
                case Gdk.Key.ISO_Left_Tab:
                    if (edit.table != null) {
                        move_cell (shift ? -1 : 1);
                        return true;
                    }
                    insert_text ("\t");
                    return true;
                default:
                    return false;
            }
            edit.pending = null;
            bump_caret ();
            selection_changed ();
            queue_draw ();
            return true;
        }

        private void move_cell (int dir) {
            var t = edit.table;
            int r = edit.row, c = edit.col;
            do {
                c += dir;
                if (c >= t.cols) {
                    c = 0;
                    r++;
                }
                if (c < 0) {
                    c = t.cols - 1;
                    r--;
                }
                if (r < 0 || r >= t.rows) return;
            } while (t.cells[r][c].covered);
            begin_cell_edit (t, r, c);
            edit.anchor = TextPos (0, 0);
            edit.caret = edit.story.end_pos ();
            queue_draw ();
        }

        private void new_paragraph () {
            doc.checkpoint (_("New Paragraph"), "typing:%d".printf (edit.story.id));
            if (edit.has_selection ()) {
                TextPos a, b;
                edit.ordered (out a, out b);
                edit.story.delete_range (a, b);
                edit.collapse (a);
            }
            var cur = edit.story.paras[edit.caret.para];
            bool at_end = edit.caret.offset >= cur.length ();
            var np = edit.story.split_paragraph (edit.caret);
            if (at_end) {
                var st = pub.styles.find_paragraph (cur.style);
                if (st != null && st.next != "" && pub.styles.find_paragraph (st.next) != null) {
                    var p = edit.story.paras[np.para];
                    p.style = st.next;
                    p.fmt = new ParaFormat ();
                    foreach (var r in p.runs) r.fmt = new CharFormat ();
                }
            }
            edit.collapse (np);
            doc.touch ();
            text_edited ();
        }

        public string selected_text () {
            if (edit == null || !edit.has_selection ()) return "";
            TextPos a, b;
            edit.ordered (out a, out b);
            return edit.story.plain_range (a, b).replace ("\u2028", "\n").replace (OBJ_STR, "");
        }

        public Story? selected_fragment () {
            if (edit == null || !edit.has_selection ()) return null;
            TextPos a, b;
            edit.ordered (out a, out b);
            return edit.story.copy_range (a, b);
        }

        public void delete_selected_text () {
            if (edit == null || !edit.has_selection ()) return;
            doc.checkpoint (_("Cut"));
            TextPos a, b;
            edit.ordered (out a, out b);
            edit.story.delete_range (a, b);
            edit.collapse (a);
            doc.touch ();
            text_edited ();
        }

        public void paste_fragment (Story frag) {
            if (edit == null) return;
            doc.checkpoint (_("Paste"));
            if (edit.has_selection ()) {
                TextPos a, b;
                edit.ordered (out a, out b);
                edit.story.delete_range (a, b);
                edit.collapse (a);
            }
            var pos = edit.story.insert_story (edit.caret, frag);
            edit.collapse (pos);
            doc.touch ();
            text_edited ();
        }

        public void reselect_ids (int[] ids) {
            selection.clear ();
            foreach (int id in ids) {
                var r = pub.find_item (id);
                if (r != null && r.group == null) selection.add (r.item);
            }
            selection_changed ();
        }

        public int[] selected_ids () {
            int[] ids = {};
            foreach (var it in selection) ids += it.id;
            return ids;
        }

        public void popup_at (Popover p, double x, double y) {
            var r = Gdk.Rectangle ();
            r.x = (int) x;
            r.y = (int) y;
            r.width = 1;
            r.height = 1;
            p.pointing_to = r;
        }
    }
}
