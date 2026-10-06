namespace Singularity.Apps.Publish {

    public class LineGroup {
        public Item item;
        public double ox;
        public double oy;
        public Gee.ArrayList<LaidLine> lines;
        public int page;
        public bool left;

        public LineGroup (Item item, double ox, double oy, Gee.ArrayList<LaidLine> lines, int page, bool left) {
            this.item = item;
            this.ox = ox;
            this.oy = oy;
            this.lines = lines;
            this.page = page;
            this.left = left;
        }
    }

    public class EditState {
        public Story story;
        public TextFrame? frame = null;
        public TableItem? table = null;
        public int row = 0;
        public int col = 0;
        public int page = -1;
        public bool left = false;
        public TextPos caret;
        public TextPos anchor;
        public Run? pending = null;
        public double goal_x = double.NAN;

        public EditState (Story story) {
            this.story = story;
            caret = TextPos (0, 0);
            anchor = TextPos (0, 0);
        }

        public bool has_selection () {
            return !caret.equals (anchor);
        }

        public void ordered (out TextPos a, out TextPos b) {
            if (caret.compare (anchor) <= 0) {
                a = caret;
                b = anchor;
            } else {
                a = anchor;
                b = caret;
            }
        }

        public void collapse (TextPos p) {
            caret = story.clamp (p);
            anchor = caret;
            goal_x = double.NAN;
        }

        public void extend (TextPos p) {
            caret = story.clamp (p);
            goal_x = double.NAN;
        }
    }

    public class TextNav {
        public static TextPos left (Story s, TextPos p, bool word) {
            if (!word) {
                if (p.offset > 0) return TextPos (p.para, p.offset - 1);
                if (p.para > 0) return TextPos (p.para - 1, s.paras[p.para - 1].length ());
                return p;
            }
            var cur = p;
            if (cur.offset == 0) return left (s, cur, false);
            string t = s.paras[cur.para].text ();
            int o = cur.offset;
            while (o > 0 && !Story.is_word_char (t.get_char (t.index_of_nth_char (o - 1)))) o--;
            while (o > 0 && Story.is_word_char (t.get_char (t.index_of_nth_char (o - 1)))) o--;
            return TextPos (cur.para, o);
        }

        public static TextPos right (Story s, TextPos p, bool word) {
            int len = s.paras[p.para].length ();
            if (!word) {
                if (p.offset < len) return TextPos (p.para, p.offset + 1);
                if (p.para < s.paras.size - 1) return TextPos (p.para + 1, 0);
                return p;
            }
            if (p.offset >= len) return right (s, p, false);
            string t = s.paras[p.para].text ();
            int o = p.offset;
            while (o < len && Story.is_word_char (t.get_char (t.index_of_nth_char (o)))) o++;
            while (o < len && !Story.is_word_char (t.get_char (t.index_of_nth_char (o)))) o++;
            return TextPos (p.para, o);
        }
    }
}
