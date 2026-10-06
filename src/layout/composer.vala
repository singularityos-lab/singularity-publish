namespace Singularity.Apps.Publish {

    public class ComposedLine {
        public int start;
        public int end;
        public int next;
        public bool hyphen;
        public double ratio;
        public double width;

        public ComposedLine (int start, int end, int next, bool hyphen, double ratio, double width) {
            this.start = start;
            this.end = end;
            this.next = next;
            this.hyphen = hyphen;
            this.ratio = ratio;
            this.width = width;
        }
    }

    public class ComposerBreak {
        public int ci;
        public int end_ci;
        public int next_ci;
        public double penalty;
        public bool flagged;
        public bool hyphen;
        public bool forced;
    }

    public class ComposerNode {
        public int brk;
        public int line;
        public int fitness;
        public int hyphens;
        public double demerits;
        public double ratio;
        public ComposerNode? prev;
    }

    public class ParagraphComposer {
        public const double INFINITY = 10000;
        public double line_penalty = 10;
        public double flagged_demerits = 3000;
        public double fitness_demerits = 100;
        public double hyphen_penalty = 50;

        private double[] xs = {};
        private int[] byte_of = {};
        private unichar[] chars = {};
        private Gee.ArrayList<ComposerBreak> breaks = new Gee.ArrayList<ComposerBreak> ();
        private double space_w = 3;
        private double hyphen_w = 3;
        private ParaFormat pf;
        private bool justify;
        private int start_ci = 0;

        public delegate double WidthFunc (int line);

        public ParagraphComposer (ParaFormat pf) {
            this.pf = pf;
        }

        private static bool is_space (unichar c) {
            return c == ' ' || c == 0x3000;
        }

        public bool prepare (Pango.Layout full, int from) {
            unowned string text = full.get_text ();
            unowned Pango.LayoutLine? line0 = full.get_line_readonly (0);
            if (line0 == null) return false;
            foreach (unowned Pango.GlyphItem run in line0.runs) if ((run.item.analysis.level & 1) == 1) return false;
            var cl = new Gee.ArrayList<unichar> ();
            var bl = new Gee.ArrayList<int> ();
            int i = 0;
            unichar c;
            while (true) {
                int at = i;
                if (!text.get_next_char (ref i, out c)) break;
                if (c == '\t') return false;
                cl.add (c);
                bl.add (at);
            }
            bl.add (text.length);
            int n = cl.size;
            chars = new unichar[n];
            byte_of = new int[n + 1];
            for (int k = 0; k < n; k++) chars[k] = cl[k];
            for (int k = 0; k <= n; k++) byte_of[k] = bl[k];
            xs = new double[n + 1];
            for (int k = 0; k <= n; k++) {
                int b = byte_of[k];
                int xp;
                line0.index_to_x (b, false, out xp);
                xs[k] = xp / (double) Pango.SCALE;
            }
            start_ci = 0;
            while (start_ci < n && byte_of[start_ci] < from) start_ci++;
            for (int k = 0; k < n; k++) {
                if (chars[k] == ' ') {
                    space_w = double.max (0.5, xs[k + 1] - xs[k]);
                    break;
                }
            }
            var fd = full.get_font_description ();
            double size = fd != null ? fd.get_size () / (double) Pango.SCALE : 10;
            hyphen_w = double.max (space_w * 1.2, size * 0.33);
            unowned Pango.LogAttr[] attrs = full.get_log_attrs_readonly ();
            breaks.clear ();
            for (int k = start_ci + 1; k < n; k++) {
                if (k >= attrs.length) break;
                if (attrs[k].is_line_break == 0 && attrs[k].is_mandatory_break == 0) continue;
                var br = new ComposerBreak ();
                br.ci = k;
                br.next_ci = k;
                br.forced = attrs[k].is_mandatory_break != 0;
                unichar prev = chars[k - 1];
                if (is_space (prev)) {
                    int e = k - 1;
                    while (e > start_ci && is_space (chars[e - 1])) e--;
                    br.end_ci = e;
                    br.penalty = 0;
                } else if (prev == 0x00AD) {
                    br.end_ci = k;
                    br.hyphen = true;
                    br.flagged = true;
                    br.penalty = hyphen_penalty;
                } else if (prev == '-' || prev == 0x2010) {
                    br.end_ci = k;
                    br.flagged = true;
                    br.penalty = hyphen_penalty;
                } else if (prev == 0x2028 || prev == '\n') {
                    br.end_ci = k - 1;
                    br.forced = true;
                } else {
                    br.end_ci = k;
                    br.penalty = 0;
                }
                breaks.add (br);
            }
            var last = new ComposerBreak ();
            last.ci = n;
            int le = n;
            while (le > start_ci && (is_space (chars[le - 1]) || chars[le - 1] == 0x2028)) le--;
            last.end_ci = le;
            last.next_ci = n;
            last.forced = true;
            breaks.add (last);
            return true;
        }

        private void measure (int from_ci, ComposerBreak br, out double natural, out double stretch, out double shrink) {
            double w = xs[br.end_ci] - xs[from_ci];
            if (br.hyphen) w += hyphen_w;
            int spaces = 0;
            for (int k = from_ci; k < br.end_ci; k++) if (chars[k] == ' ') spaces++;
            int glyphs = int.max (0, br.end_ci - from_ci - 1);
            double wo = pf.word_opt.is_nan () ? 100 : pf.word_opt;
            double wmin = pf.word_min.is_nan () ? 80 : pf.word_min;
            double wmax = pf.word_max.is_nan () ? 133 : pf.word_max;
            double lo = pf.letter_opt.is_nan () ? 0 : pf.letter_opt;
            double lmin = pf.letter_min.is_nan () ? 0 : pf.letter_min;
            double lmax = pf.letter_max.is_nan () ? 0 : pf.letter_max;
            double go = pf.glyph_opt.is_nan () ? 100 : pf.glyph_opt;
            double gmin = pf.glyph_min.is_nan () ? 100 : pf.glyph_min;
            double gmax = pf.glyph_max.is_nan () ? 100 : pf.glyph_max;
            double base_w = w - spaces * space_w;
            natural = (base_w + glyphs * space_w * lo / 100) * go / 100 + spaces * space_w * wo / 100;
            stretch = spaces * space_w * double.max (0, wmax - wo) / 100 + glyphs * space_w * double.max (0, lmax - lo) / 100 + base_w * double.max (0, gmax - go) / 100;
            shrink = spaces * space_w * double.max (0, wo - wmin) / 100 + glyphs * space_w * double.max (0, lo - lmin) / 100 + base_w * double.max (0, go - gmin) / 100;
        }

        private static int fitness_of (double r) {
            if (r < -0.5) return 0;
            if (r <= 0.5) return 1;
            if (r <= 1) return 2;
            return 3;
        }

        public Gee.ArrayList<ComposedLine> greedy (WidthFunc width_of, bool justify_text) {
            justify = justify_text;
            var out_lines = new Gee.ArrayList<ComposedLine> ();
            int cur = start_ci;
            int line = 0;
            int bi = 0;
            while (bi < breaks.size) {
                double w = width_of (line);
                int best = -1;
                for (int k = bi; k < breaks.size; k++) {
                    var br = breaks[k];
                    if (br.hyphen) continue;
                    if (br.end_ci <= cur && k < breaks.size - 1) continue;
                    double natural, stretch, shrink;
                    measure (cur, br, out natural, out stretch, out shrink);
                    if (natural - shrink > w + 0.01 && best >= 0) break;
                    best = k;
                    if (br.forced) break;
                }
                if (best < 0) best = breaks.size - 1;
                var chosen = breaks[best];
                double natural, stretch, shrink;
                measure (cur, chosen, out natural, out stretch, out shrink);
                double ratio = natural < w ? (stretch > 0 ? (w - natural) / stretch : INFINITY) : (shrink > 0 ? (w - natural) / shrink : 0);
                out_lines.add (new ComposedLine (byte_of[cur], byte_of[chosen.end_ci], byte_of[chosen.next_ci], false, ratio, natural));
                cur = chosen.next_ci;
                bi = best + 1;
                line++;
            }
            return out_lines;
        }

        public Gee.ArrayList<ComposedLine>? compose (WidthFunc width_of, bool justify_text, bool justify_last) {
            justify = justify_text;
            Gee.ArrayList<ComposedLine>? r = run (width_of, false, 1.0, justify_last);
            if (r == null) r = run (width_of, true, 2.0, justify_last);
            if (r == null) r = run (width_of, true, INFINITY, justify_last);
            return r;
        }

        private Gee.ArrayList<ComposedLine>? run (WidthFunc width_of, bool hyphens, double tolerance, bool justify_last) {
            var active = new Gee.ArrayList<ComposerNode> ();
            var root = new ComposerNode ();
            root.brk = -1;
            root.line = 0;
            root.fitness = 1;
            root.demerits = 0;
            active.add (root);
            int limit = pf.hyph_limit > 0 ? pf.hyph_limit : 1000;
            double zone = pf.hyph_zone.is_nan () ? 0 : pf.hyph_zone;
            bool emergency = tolerance >= INFINITY;
            ComposerNode? best_final = null;
            for (int bi = 0; bi < breaks.size; bi++) {
                var br = breaks[bi];
                if (br.hyphen && !hyphens) continue;
                bool last = bi == breaks.size - 1;
                var candidates = new Gee.ArrayList<ComposerNode> ();
                var remove = new Gee.ArrayList<ComposerNode> ();
                ComposerNode? fallback = null;
                double fallback_ratio = 0;
                foreach (var a in active) {
                    int from_ci = a.brk < 0 ? start_ci : breaks[a.brk].next_ci;
                    if (from_ci >= br.end_ci && !last && !br.forced) continue;
                    double natural, stretch, shrink;
                    measure (from_ci, br, out natural, out stretch, out shrink);
                    double w = width_of (a.line);
                    if (!justify) {
                        stretch = w / 3;
                        shrink = 0;
                    }
                    double ratio;
                    bool final_loose = last && !(justify && justify_last);
                    if (natural < w) ratio = final_loose || (br.forced && !last) ? 0 : (stretch > 0 ? (w - natural) / stretch : INFINITY);
                    else if (natural > w) ratio = shrink > 0 ? (w - natural) / shrink : -INFINITY;
                    else ratio = 0;
                    if (ratio < -1 || (natural > w + 0.01 && shrink <= 0)) {
                        remove.add (a);
                        if (emergency && (fallback == null || a.demerits < fallback.demerits)) {
                            fallback = a;
                            fallback_ratio = -1;
                        }
                        continue;
                    }
                    if (br.hyphen && !justify && zone > 0) {
                        bool glue_before = false;
                        for (int ob = bi - 1; ob >= 0; ob--) {
                            var obr = breaks[ob];
                            if (obr.ci <= from_ci) break;
                            if (obr.hyphen || obr.flagged) continue;
                            double n2, s2, k2;
                            measure (from_ci, obr, out n2, out s2, out k2);
                            glue_before = w - n2 <= zone;
                            break;
                        }
                        if (glue_before) continue;
                    }
                    double bad = ratio >= INFINITY ? (emergency ? 1e9 : INFINITY) : 100 * Math.pow (Math.fabs (ratio), 3);
                    if (bad > tolerance * tolerance * tolerance * 100 && !emergency) {
                        if (br.forced) remove.add (a);
                        continue;
                    }
                    if (bad > INFINITY && !emergency) bad = INFINITY;
                    if (bad > 1e9) bad = 1e9;
                    int hy = br.flagged ? a.hyphens + 1 : 0;
                    if (hy > limit && !emergency) continue;
                    double d = Math.pow (line_penalty + bad, 2);
                    if (br.penalty > 0) d += br.penalty * br.penalty;
                    if (br.flagged && a.brk >= 0 && breaks[a.brk].flagged) d += flagged_demerits;
                    int fit = fitness_of (ratio);
                    if ((fit - a.fitness).abs () > 1) d += fitness_demerits;
                    var node = new ComposerNode ();
                    node.brk = bi;
                    node.line = a.line + 1;
                    node.fitness = fit;
                    node.hyphens = hy;
                    node.ratio = ratio;
                    node.demerits = a.demerits + d;
                    node.prev = a;
                    candidates.add (node);
                    if (br.forced) remove.add (a);
                }
                foreach (var rn in remove) active.remove (rn);
                if (candidates.size == 0 && fallback != null && emergency) {
                    var node = new ComposerNode ();
                    node.brk = bi;
                    node.line = fallback.line + 1;
                    node.fitness = 0;
                    node.ratio = fallback_ratio;
                    node.demerits = fallback.demerits + INFINITY;
                    node.prev = fallback;
                    candidates.add (node);
                }
                var by_class = new Gee.HashMap<string, ComposerNode> ();
                foreach (var c in candidates) {
                    string key = "%d:%d".printf (c.line, c.fitness);
                    if (!by_class.has_key (key) || by_class[key].demerits > c.demerits) by_class[key] = c;
                }
                foreach (var c in by_class.values) {
                    if (last) {
                        if (best_final == null || c.demerits < best_final.demerits) best_final = c;
                    } else {
                        active.add (c);
                    }
                }
                if (active.size == 0 && !last) {
                    if (!emergency) return null;
                }
                if (active.size > 400) {
                    active.sort ((x, y) => x.demerits < y.demerits ? -1 : (x.demerits > y.demerits ? 1 : 0));
                    while (active.size > 200) active.remove_at (active.size - 1);
                }
            }
            if (best_final == null) return null;
            var chain = new Gee.ArrayList<ComposerNode> ();
            for (var n = best_final; n != null && n.brk >= 0; n = n.prev) chain.insert (0, n);
            var out_lines = new Gee.ArrayList<ComposedLine> ();
            int cur = start_ci;
            foreach (var n in chain) {
                var br = breaks[n.brk];
                double natural, stretch, shrink;
                measure (cur, br, out natural, out stretch, out shrink);
                out_lines.add (new ComposedLine (byte_of[cur], byte_of[br.end_ci], byte_of[br.next_ci], br.hyphen, n.ratio, natural));
                cur = br.next_ci;
            }
            return out_lines;
        }
    }
}
