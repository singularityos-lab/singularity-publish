namespace Singularity.Apps.Publish {

    public enum LiquidMode {
        SCALE,
        RECENTER,
        OBJECT,
        FIXED;

        public static string[] labels () {
            return { _("Scale"), _("Re-center"), _("Object Based"), _("Keep Position") };
        }
    }

    public class Liquid {
        public const int PIN_LEFT = 1;
        public const int PIN_RIGHT = 2;
        public const int PIN_TOP = 4;
        public const int PIN_BOTTOM = 8;
        public const int FLEX_W = 16;
        public const int FLEX_H = 32;

        public static void apply (Item it, double ow, double oh, double nw, double nh) {
            double dw = nw - ow, dh = nh - oh;
            switch ((LiquidMode) it.liquid_mode) {
                case LiquidMode.SCALE:
                    double sx = nw / ow, sy = nh / oh;
                    it.x *= sx;
                    it.y *= sy;
                    it.w *= sx;
                    it.h *= sy;
                    break;
                case LiquidMode.RECENTER:
                    it.x += dw / 2;
                    it.y += dh / 2;
                    break;
                case LiquidMode.OBJECT:
                    int p = it.liquid_pins;
                    bool l = (p & PIN_LEFT) != 0, r = (p & PIN_RIGHT) != 0, t = (p & PIN_TOP) != 0, b = (p & PIN_BOTTOM) != 0;
                    if ((p & FLEX_W) != 0 && l && r) it.w += dw;
                    else if ((p & FLEX_W) != 0) {
                        double nwid = it.w * nw / ow;
                        if (r && !l) it.x += dw + it.w - nwid;
                        else if (!l) it.x = (it.x + it.w / 2) * nw / ow - nwid / 2;
                        it.w = nwid;
                    } else if (r && !l) it.x += dw;
                    else if (!l) it.x += dw / 2;
                    if ((p & FLEX_H) != 0 && t && b) it.h += dh;
                    else if ((p & FLEX_H) != 0) {
                        double nhei = it.h * nh / oh;
                        if (b && !t) it.y += dh + it.h - nhei;
                        else if (!t) it.y = (it.y + it.h / 2) * nh / oh - nhei / 2;
                        it.h = nhei;
                    } else if (b && !t) it.y += dh;
                    else if (!t) it.y += dh / 2;
                    break;
                default:
                    break;
            }
            it.w = double.max (1, it.w);
            it.h = double.max (1, it.h);
        }
    }

    public class AlternateLayouts {
        public static Gee.ArrayList<string> names (Publication pub) {
            var list = new Gee.ArrayList<string> ();
            foreach (var pg in pub.pages) {
                string n = pg.layout_name != "" ? pg.layout_name : "";
                if (!list.contains (n)) list.add (n);
            }
            return list;
        }

        public static int create (Publication pub, string source, string name, double nw, double nh) {
            var src_pages = new Gee.ArrayList<int> ();
            for (int i = 0; i < pub.pages.size; i++) if (pub.pages[i].layout_name == source) src_pages.add (i);
            if (src_pages.size == 0) return -1;
            int first = pub.pages.size;
            var story_map = new Gee.HashMap<int, int> ();
            foreach (int pi in src_pages) {
                var sp = pub.pages[pi];
                double ow = pub.page_w (pi), oh = pub.page_h (pi);
                var np = pub.add_page (-1, sp.master);
                np.layout_name = name;
                np.width = nw;
                np.height = nh;
                np.hide_master = sp.hide_master;
                foreach (var it in sp.items) {
                    var c = it.clone ();
                    remap (pub, c, story_map);
                    Liquid.apply (c, ow, oh, nw, nh);
                    np.items.add (c);
                }
            }
            var sec = new Section (first);
            sec.name = name;
            sec.start_number = 1;
            pub.sections.add (sec);
            return first;
        }

        private static void remap (Publication pub, Item it, Gee.HashMap<int, int> story_map) {
            int old_id = it.id;
            it.id = pub.next_id ();
            var t = it as TextFrame;
            if (t != null) {
                int old = t.story;
                if (!story_map.has_key (old)) {
                    var st = pub.story (old).clone ();
                    st.id = pub.next_id ();
                    st.frames.clear ();
                    st.source_story = old;
                    st.link_path = "";
                    pub.stories[st.id] = st;
                    story_map[old] = st.id;
                }
                var ns = pub.story (story_map[old]);
                var src = pub.story (old);
                int at = src.frames.index_of (old_id);
                while (ns.frames.size <= at) ns.frames.add (0);
                if (at >= 0) ns.frames[at] = t.id;
                else ns.frames.add (t.id);
                ns.frames.remove_all (new Gee.ArrayList<int>.wrap ({ 0 }));
                t.story = ns.id;
            }
            var tb = it as TableItem;
            if (tb != null) foreach (var row in tb.cells) foreach (var c in row) c.story.id = pub.next_id ();
            var g = it as GroupItem;
            if (g != null) foreach (var c in g.children) remap (pub, c, story_map);
        }

        public static int update (Publication pub) {
            int n = 0;
            foreach (var st in pub.stories.values) {
                if (st.source_story == 0 || !pub.stories.has_key (st.source_story)) continue;
                var src = pub.stories[st.source_story];
                st.paras.clear ();
                foreach (var p in src.paras) st.paras.add (p.clone ());
                n++;
            }
            return n;
        }
    }
}
