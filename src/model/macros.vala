namespace Singularity.Apps.Publish {

    public errordomain MacroError {
        SYNTAX,
        FAILED
    }

    public abstract class MacroHost {
        public abstract Publication publication ();
        public abstract bool run_action (string name, string? param);
        public abstract void insert_text (string text);
        public abstract void go_to_page (int index);
        public abstract void select_items (Gee.List<Item> items);
        public abstract Gee.List<Item> page_items (int index);
        public abstract void format_chars (string key, string value);
        public abstract void apply_style (string name);
        public abstract void export_pdf (string path) throws Error;
        public abstract void changed ();
        public abstract void message (string text);
    }

    public class MacroValue {
        public bool is_num;
        public double num;
        public string str;

        public MacroValue.number (double v) {
            is_num = true;
            num = v;
            str = "";
        }

        public MacroValue.text (string v) {
            is_num = false;
            num = 0;
            str = v;
        }

        public MacroValue.flag (bool v) {
            is_num = true;
            num = v ? 1 : 0;
            str = "";
        }

        public double to_num () {
            if (is_num) return num;
            double d;
            return double.try_parse (str.strip (), out d) ? d : 0;
        }

        public bool truthy () {
            return is_num ? num != 0 : (str != "" && str.down () != "false" && str != "0");
        }

        public string to_string () {
            if (!is_num) return str;
            if (num == Math.floor (num) && Math.fabs (num) < 1e15) return "%.0f".printf (num);
            return "%g".printf (num);
        }
    }

    public class MacroCommand {
        public string name;
        public Gee.ArrayList<string> args = new Gee.ArrayList<string> ();
        public Gee.ArrayList<MacroCommand> body = new Gee.ArrayList<MacroCommand> ();
        public Gee.ArrayList<MacroCommand> branches = new Gee.ArrayList<MacroCommand> ();
        public string raw = "";
        public int line;

        public MacroCommand (string name, int line) {
            this.name = name;
            this.line = line;
        }

        public string arg (int i, string fallback = "") {
            return i < args.size ? args[i] : fallback;
        }
    }

    public class MacroEngine {
        public int steps = 0;
        public int max_steps = 100000;
        public int current_page = 0;
        public Gee.HashMap<string, MacroValue> vars = new Gee.HashMap<string, MacroValue> ();
        public Item? current_item = null;
        public Story? current_story = null;
        public int current_para = -1;
        private bool breaking = false;
        private MacroHost? active_host = null;

        public static string[] commands () {
            return { "action", "type", "page", "replace", "font", "size", "color", "bold", "italic", "underline", "style", "select-all", "deselect", "new-page", "repeat", "for-each-page", "for-each-text-frame", "export-pdf", "save", "message", "end",
                "set", "if", "elif", "else", "while", "for", "break", "for-each-item", "for-each-paragraph", "set-item", "set-paragraph", "define-style", "add-text-frame", "add-shape", "delete-item" };
        }

        public static string[] events () {
            return { "open", "save", "print", "export", "new-page" };
        }

        public static string event_label (string e) {
            switch (e) {
                case "open": return _("When the Publication Opens");
                case "save": return _("Before Saving");
                case "print": return _("Before Printing");
                case "export": return _("Before Exporting");
                case "new-page": return _("When a Page Is Added");
                default: return _("Only When Run");
            }
        }

        public static MacroDef? for_event (Publication pub, string ev) {
            foreach (var m in pub.macros) if (m.event == ev) return m;
            return null;
        }

        private static bool opens_block (string name) {
            return name == "repeat" || name == "for-each-page" || name == "for-each-text-frame" || name == "if" || name == "while" || name == "for" || name == "for-each-item" || name == "for-each-paragraph";
        }

        private static bool expression_command (string name) {
            return name == "set" || name == "if" || name == "elif" || name == "while" || name == "for";
        }

        public static Gee.ArrayList<string> tokenize (string line) throws MacroError {
            var toks = new Gee.ArrayList<string> ();
            var sb = new StringBuilder ();
            bool quoted = false, any = false;
            int depth = 0;
            unichar c;
            int i = 0;
            while (line.get_next_char (ref i, out c)) {
                if (!quoted && c == '{') depth++;
                if (!quoted && c == '}' && depth > 0) depth--;
                if (depth > 0 && !quoted) {
                    sb.append_unichar (c);
                    any = true;
                    continue;
                }
                if (quoted) {
                    if (c == '\\' && i < line.length) {
                        unichar n;
                        line.get_next_char (ref i, out n);
                        if (n == 'n') sb.append_c ('\n');
                        else if (n == 't') sb.append_c ('\t');
                        else sb.append_unichar (n);
                    } else if (c == '"') {
                        quoted = false;
                    } else {
                        sb.append_unichar (c);
                    }
                    continue;
                }
                if (c == '"') {
                    quoted = true;
                    any = true;
                    continue;
                }
                if (c == ' ' || c == '\t') {
                    if (any) toks.add (sb.str);
                    sb.truncate ();
                    any = false;
                    continue;
                }
                sb.append_unichar (c);
                any = true;
            }
            if (quoted) throw new MacroError.SYNTAX (_("Unclosed quotation mark"));
            if (any) toks.add (sb.str);
            return toks;
        }

        public static Gee.ArrayList<MacroCommand> parse (string script) throws MacroError {
            var root = new Gee.ArrayList<MacroCommand> ();
            var stack = new Gee.ArrayList<Gee.ArrayList<MacroCommand>> ();
            var owners = new Gee.ArrayList<MacroCommand?> ();
            stack.add (root);
            owners.add (null);
            string[] lines = script.replace ("\r\n", "\n").split ("\n");
            for (int i = 0; i < lines.length; i++) {
                string l = lines[i].strip ();
                if (l == "" || l.has_prefix ("#")) continue;
                Gee.ArrayList<string> toks;
                try {
                    toks = tokenize (l);
                } catch (MacroError e) {
                    throw new MacroError.SYNTAX (_("Line %d: %s").printf (i + 1, e.message));
                }
                if (toks.size == 0) continue;
                string name = toks[0].down ();
                bool known = false;
                foreach (string k in commands ()) if (k == name) known = true;
                if (!known) throw new MacroError.SYNTAX (_("Line %d: unknown command \"%s\"").printf (i + 1, toks[0]));
                if (name == "end") {
                    if (stack.size <= 1) throw new MacroError.SYNTAX (_("Line %d: \"end\" without a matching block").printf (i + 1));
                    stack.remove_at (stack.size - 1);
                    owners.remove_at (owners.size - 1);
                    continue;
                }
                var cmd = new MacroCommand (name, i + 1);
                for (int k = 1; k < toks.size; k++) cmd.args.add (toks[k]);
                int sp = l.index_of_char (' ');
                cmd.raw = sp > 0 ? l.substring (sp + 1).strip () : "";
                if (expression_command (name) && name != "set" && name != "for" && cmd.raw == "") throw new MacroError.SYNTAX (_("Line %d: \"%s\" needs a condition").printf (i + 1, name));
                if (name == "elif" || name == "else") {
                    var owner = owners[owners.size - 1];
                    if (owner == null || owner.name != "if") throw new MacroError.SYNTAX (_("Line %d: \"%s\" without a matching \"if\"").printf (i + 1, name));
                    if (owner.branches.size > 0 && owner.branches[owner.branches.size - 1].name == "else") throw new MacroError.SYNTAX (_("Line %d: nothing can follow \"else\"").printf (i + 1));
                    owner.branches.add (cmd);
                    stack[stack.size - 1] = cmd.body;
                    continue;
                }
                if (name == "set" && cmd.args.size < 2) throw new MacroError.SYNTAX (_("Line %d: set needs a name and a value").printf (i + 1));
                if (name == "for" && (cmd.args.size < 5 || cmd.args[1].down () != "from" || cmd.args[3].down () != "to")) throw new MacroError.SYNTAX (_("Line %d: write for NAME from FIRST to LAST").printf (i + 1));
                stack[stack.size - 1].add (cmd);
                if (opens_block (name)) {
                    stack.add (cmd.body);
                    owners.add (cmd);
                }
            }
            if (stack.size > 1) throw new MacroError.SYNTAX (_("A block is missing its \"end\""));
            return root;
        }

        public int run (MacroHost host, string script) throws Error {
            var cmds = parse (script);
            steps = 0;
            breaking = false;
            active_host = host;
            exec (host, cmds);
            host.changed ();
            return steps;
        }

        private void exec (MacroHost host, Gee.ArrayList<MacroCommand> cmds) throws Error {
            foreach (var c in cmds) {
                if (breaking) return;
                if (++steps > max_steps) throw new MacroError.FAILED (_("The macro stopped after %d steps").printf (max_steps));
                exec_one (host, expand (c));
            }
        }

        private MacroCommand expand (MacroCommand c) throws Error {
            if (expression_command (c.name) || c.name == "else") return c;
            bool any = false;
            foreach (string a in c.args) if (a.contains ("{") || a.has_prefix ("$")) any = true;
            if (!any) return c;
            var e = new MacroCommand (c.name, c.line);
            e.body = c.body;
            e.branches = c.branches;
            e.raw = c.raw;
            foreach (string a in c.args) e.args.add (interpolate (a, c.line));
            return e;
        }

        public string interpolate (string a, int line) throws Error {
            if (a.has_prefix ("$") && !a.contains ("{")) {
                string n = a.substring (1);
                if (vars.has_key (n)) return vars[n].to_string ();
                throw new MacroError.FAILED (_("Line %d: there is no variable \"%s\"").printf (line, n));
            }
            var sb = new StringBuilder ();
            int i = 0;
            while (i < a.length) {
                int open = a.index_of_char ('{', i);
                if (open < 0) {
                    sb.append (a.substring (i));
                    break;
                }
                int close = a.index_of_char ('}', open);
                if (close < 0) throw new MacroError.SYNTAX (_("Line %d: \"{\" without \"}\"").printf (line));
                sb.append (a.substring (i, open - i));
                sb.append (eval (a.substring (open + 1, close - open - 1), line).to_string ());
                i = close + 1;
            }
            return sb.str;
        }

        public MacroValue eval (string expr, int line = 0) throws Error {
            var p = new MacroExpr (this, expr, line);
            return p.parse ();
        }

        private Gee.ArrayList<Paragraph>? current_paragraphs () {
            if (current_story != null) return current_story.paras;
            var t = current_item as TextFrame;
            if (t != null && active_host != null) return active_host.publication ().story (t.story).paras;
            return null;
        }

        public MacroValue resolve (string name, int line) throws Error {
            if (vars.has_key (name)) return vars[name];
            var pub = active_host.publication ();
            switch (name) {
                case "true": return new MacroValue.flag (true);
                case "false": return new MacroValue.flag (false);
                case "doc.title": return new MacroValue.text (pub.meta.title);
                case "doc.width": return new MacroValue.number (pub.settings.width);
                case "doc.height": return new MacroValue.number (pub.settings.height);
                case "doc.pages":
                case "pages.count": return new MacroValue.number (pub.pages.size);
                case "page.number": return new MacroValue.number (current_page + 1);
                case "page.items": return new MacroValue.number (current_page < pub.pages.size ? pub.pages[current_page].items.size : 0);
                case "styles.count": return new MacroValue.number (pub.styles.paragraph.size);
                default: break;
            }
            if (name.has_prefix ("item.")) {
                var it = current_item;
                string prop = name.substring (5);
                if (prop == "exists") return new MacroValue.flag (it != null);
                if (it == null) throw new MacroError.FAILED (_("Line %d: there is no current object; use for-each-item or select one").printf (line));
                switch (prop) {
                    case "kind": return new MacroValue.text (it.kind.to_string ());
                    case "name": return new MacroValue.text (it.name);
                    case "x": return new MacroValue.number (it.x);
                    case "y": return new MacroValue.number (it.y);
                    case "width": return new MacroValue.number (it.w);
                    case "height": return new MacroValue.number (it.h);
                    case "rotation": return new MacroValue.number (it.rotation);
                    case "alt": return new MacroValue.text (it.alt_text);
                    case "text":
                        var t = it as TextFrame;
                        return new MacroValue.text (t != null ? pub.story (t.story).plain_text () : "");
                    case "overset":
                        var t2 = it as TextFrame;
                        if (t2 == null) return new MacroValue.flag (false);
                        return new MacroValue.flag (new LayoutCache (pub).story (t2.story).overset);
                    default: break;
                }
            }
            if (name.has_prefix ("paragraph.")) {
                var paras = current_paragraphs ();
                if (paras == null || current_para < 0 || current_para >= paras.size) throw new MacroError.FAILED (_("Line %d: there is no current paragraph; use for-each-paragraph").printf (line));
                var para = paras[current_para];
                switch (name.substring (10)) {
                    case "text": return new MacroValue.text (para.text ());
                    case "style": return new MacroValue.text (para.style);
                    case "number": return new MacroValue.number (current_para + 1);
                    default: break;
                }
            }
            throw new MacroError.FAILED (_("Line %d: unknown name \"%s\"").printf (line, name));
        }

        public MacroValue call (string fn, Gee.ArrayList<MacroValue> a, int line) throws Error {
            var pub = active_host.publication ();
            string s0 = a.size > 0 ? a[0].to_string () : "";
            switch (fn) {
                case "len": return new MacroValue.number (s0.char_count ());
                case "upper": return new MacroValue.text (s0.up ());
                case "lower": return new MacroValue.text (s0.down ());
                case "trim": return new MacroValue.text (s0.strip ());
                case "contains": return new MacroValue.flag (a.size > 1 && s0.contains (a[1].to_string ()));
                case "starts": return new MacroValue.flag (a.size > 1 && s0.has_prefix (a[1].to_string ()));
                case "ends": return new MacroValue.flag (a.size > 1 && s0.has_suffix (a[1].to_string ()));
                case "round": return new MacroValue.number (Math.round (a.size > 0 ? a[0].to_num () : 0));
                case "floor": return new MacroValue.number (Math.floor (a.size > 0 ? a[0].to_num () : 0));
                case "num": return new MacroValue.number (a.size > 0 ? a[0].to_num () : 0);
                case "str": return new MacroValue.text (s0);
                case "has_style": return new MacroValue.flag (pub.styles.find_paragraph (s0) != null);
                case "count":
                    int n = 0;
                    foreach (var pg in pub.pages) foreach (var it in pg.items) if (s0 == "" || it.kind.to_string () == s0) n++;
                    return new MacroValue.number (n);
                default:
                    throw new MacroError.FAILED (_("Line %d: unknown function \"%s\"").printf (line, fn));
            }
        }

        private static string color_spec (string v) {
            if (v == "" || v.down () == "none") return ColorRef.NONE;
            if (v.has_prefix ("#") || v.has_prefix ("swatch:") || v.has_prefix ("cmyk:")) return v;
            return ColorRef.swatch (v);
        }

        private static int align_of (string v) {
            switch (v.down ()) {
                case "center": return (int) TextAlign.CENTER;
                case "right": return (int) TextAlign.RIGHT;
                case "justify": return (int) TextAlign.JUSTIFY;
                default: return (int) TextAlign.LEFT;
            }
        }

        private void set_item_prop (Publication pub, Item it, string prop, string v, int line) throws Error {
            switch (prop) {
                case "name": it.name = v; break;
                case "x": it.x = Units.parse_num (v, it.x); break;
                case "y": it.y = Units.parse_num (v, it.y); break;
                case "width": it.w = double.max (1, Units.parse_num (v, it.w)); break;
                case "height": it.h = double.max (1, Units.parse_num (v, it.h)); break;
                case "rotation": it.rotation = Units.parse_num (v, 0); break;
                case "opacity": it.opacity = Units.parse_num (v, 100).clamp (0, 100) / 100; break;
                case "fill": it.fill = new Fill.solid (color_spec (v)); break;
                case "stroke": it.stroke.color = color_spec (v); break;
                case "alt": it.alt_text = v; break;
                case "locked": it.locked = on_value (v); break;
                case "text":
                    var t = it as TextFrame;
                    if (t == null) throw new MacroError.FAILED (_("Line %d: only text frames have text").printf (line));
                    var st = pub.story (t.story);
                    string style = st.paras.size > 0 ? st.paras[0].style : StyleSheet.BASIC;
                    st.paras.clear ();
                    foreach (string l in v.split ("\n")) st.paras.add (new Paragraph.with_text (l, style));
                    break;
                default:
                    throw new MacroError.FAILED (_("Line %d: objects have no property \"%s\"").printf (line, prop));
            }
        }

        private void define_style (Publication pub, MacroCommand c) throws Error {
            string name = c.arg (0);
            if (name == "") throw new MacroError.SYNTAX (_("Line %d: define-style needs a name").printf (c.line));
            var st = pub.styles.find_paragraph (name);
            if (st == null) {
                st = new ParagraphStyle (name, StyleSheet.BASIC);
                pub.styles.paragraph.add (st);
            }
            for (int i = 1; i + 1 < c.args.size; i += 2) {
                string v = c.args[i + 1];
                switch (c.args[i]) {
                    case "font": st.chars.font = v; break;
                    case "size": st.chars.size = Units.parse_num (v, 11); break;
                    case "color": st.chars.color = color_spec (v); break;
                    case "bold": st.chars.bold = on_value (v) ? 1 : 0; break;
                    case "italic": st.chars.italic = on_value (v) ? 1 : 0; break;
                    case "leading": st.para.leading = Units.parse_num (v, 0); break;
                    case "align": st.para.align = align_of (v); break;
                    case "space-before": st.para.space_before = Units.parse_num (v, 0); break;
                    case "space-after": st.para.space_after = Units.parse_num (v, 0); break;
                    case "based-on":
                        if (pub.styles.find_paragraph (v) == null) throw new MacroError.FAILED (_("Line %d: there is no paragraph style \"%s\"").printf (c.line, v));
                        st.based_on = v;
                        break;
                    default:
                        throw new MacroError.FAILED (_("Line %d: styles have no property \"%s\"").printf (c.line, c.args[i]));
                }
            }
        }

        private Gee.ArrayList<Item> page_list (Publication pub) {
            int pi = current_page.clamp (0, int.max (0, pub.pages.size - 1));
            return pub.pages[pi].items;
        }

        private static bool on_value (string v) {
            string l = v.down ();
            return l == "" || l == "on" || l == "yes" || l == "true" || l == "1";
        }

        private void exec_one (MacroHost host, MacroCommand c) throws Error {
            var pub = host.publication ();
            active_host = host;
            switch (c.name) {
                case "action":
                    if (c.args.size == 0) throw new MacroError.SYNTAX (_("Line %d: action needs a name").printf (c.line));
                    if (!host.run_action (c.arg (0), c.args.size > 1 ? c.arg (1) : null)) throw new MacroError.FAILED (_("Line %d: there is no command \"%s\"").printf (c.line, c.arg (0)));
                    break;
                case "type":
                    host.insert_text (string.joinv (" ", c.args.to_array ()));
                    break;
                case "page":
                    int n = int.parse (c.arg (0, "1"));
                    current_page = (n - 1).clamp (0, pub.pages.size - 1);
                    host.go_to_page (current_page);
                    break;
                case "replace":
                    bool mc = c.args.contains ("case"), ww = c.args.contains ("word");
                    int total = 0;
                    foreach (var s in pub.stories.values) total += s.replace_all (c.arg (0), c.arg (1), mc, ww);
                    pub.walk ((r) => {
                        var tb = r.item as TableItem;
                        if (tb != null) foreach (var row in tb.cells) foreach (var cell in row) total += cell.story.replace_all (c.arg (0), c.arg (1), mc, ww);
                        return true;
                    });
                    break;
                case "font":
                    host.format_chars ("font", c.arg (0));
                    break;
                case "size":
                    host.format_chars ("size", c.arg (0));
                    break;
                case "color":
                    host.format_chars ("color", c.arg (0));
                    break;
                case "bold":
                case "italic":
                case "underline":
                    host.format_chars (c.name, on_value (c.arg (0)) ? "1" : "0");
                    break;
                case "style":
                    if (pub.styles.find_paragraph (c.arg (0)) == null) throw new MacroError.FAILED (_("Line %d: there is no paragraph style \"%s\"").printf (c.line, c.arg (0)));
                    host.apply_style (c.arg (0));
                    break;
                case "select-all":
                    host.run_action ("select-all", null);
                    break;
                case "deselect":
                    host.run_action ("deselect", null);
                    break;
                case "new-page":
                    host.run_action ("add-page", null);
                    break;
                case "repeat":
                    int times = int.parse (c.arg (0, "1")).clamp (0, 10000);
                    for (int i = 0; i < times; i++) exec (host, c.body);
                    break;
                case "for-each-page":
                    int count = pub.pages.size;
                    for (int i = 0; i < count && i < pub.pages.size; i++) {
                        current_page = i;
                        host.go_to_page (i);
                        exec (host, c.body);
                    }
                    break;
                case "for-each-text-frame":
                    for (int i = 0; i < pub.pages.size; i++) {
                        var frames = new Gee.ArrayList<Item> ();
                        foreach (var it in host.page_items (i)) if (it is TextFrame) frames.add (it);
                        foreach (var f in frames) {
                            host.go_to_page (i);
                            var one = new Gee.ArrayList<Item> ();
                            one.add (f);
                            host.select_items (one);
                            exec (host, c.body);
                        }
                    }
                    break;
                case "export-pdf":
                    if (c.arg (0) == "") throw new MacroError.SYNTAX (_("Line %d: export-pdf needs a file name").printf (c.line));
                    host.export_pdf (c.arg (0));
                    break;
                case "save":
                    host.run_action ("save", null);
                    break;
                case "message":
                    host.message (string.joinv (" ", c.args.to_array ()));
                    break;
                case "set":
                    string vname = c.arg (0);
                    string expr = c.raw.substring (c.raw.index_of (vname) + vname.length).strip ();
                    if (expr.has_prefix ("=")) expr = expr.substring (1).strip ();
                    vars[vname] = eval (expr, c.line);
                    break;
                case "if":
                    if (eval (c.raw, c.line).truthy ()) {
                        exec (host, c.body);
                    } else {
                        foreach (var b in c.branches) {
                            if (b.name == "else" || eval (b.raw, b.line).truthy ()) {
                                exec (host, b.body);
                                break;
                            }
                        }
                    }
                    break;
                case "while":
                    while (!breaking && eval (c.raw, c.line).truthy ()) {
                        if (++steps > max_steps) throw new MacroError.FAILED (_("The macro stopped after %d steps").printf (max_steps));
                        exec (host, c.body);
                    }
                    breaking = false;
                    break;
                case "for":
                    string fv = c.arg (0);
                    double first = eval (c.arg (2), c.line).to_num (), last = eval (c.arg (4), c.line).to_num ();
                    double stepv = c.args.size > 6 && c.arg (5).down () == "step" ? eval (c.arg (6), c.line).to_num () : (last >= first ? 1 : -1);
                    if (stepv == 0) throw new MacroError.FAILED (_("Line %d: step cannot be zero").printf (c.line));
                    for (double v = first; stepv > 0 ? v <= last : v >= last; v += stepv) {
                        vars[fv] = new MacroValue.number (v);
                        exec (host, c.body);
                        if (breaking) break;
                    }
                    breaking = false;
                    break;
                case "break":
                    breaking = true;
                    break;
                case "for-each-item":
                    string kind = c.arg (0).down ();
                    int saved_page = current_page;
                    var saved_it = current_item;
                    for (int i = 0; i < pub.pages.size; i++) {
                        var list = new Gee.ArrayList<Item> ();
                        foreach (var it in pub.pages[i].items) if (kind == "" || it.kind.to_string () == kind || (kind == "text" && it is TextFrame)) list.add (it);
                        foreach (var it in list) {
                            current_page = i;
                            current_item = it;
                            exec (host, c.body);
                            if (breaking) break;
                        }
                        if (breaking) break;
                    }
                    current_page = saved_page;
                    current_item = saved_it;
                    breaking = false;
                    break;
                case "for-each-paragraph":
                    var targets = new Gee.ArrayList<Story> ();
                    var cur_t = current_item as TextFrame;
                    if (cur_t != null) targets.add (pub.story (cur_t.story));
                    else targets.add_all (pub.stories.values);
                    var saved_item = current_item;
                    foreach (var st in targets) {
                        current_story = st;
                        for (int i = 0; i < st.paras.size; i++) {
                            current_para = i;
                            exec (host, c.body);
                            if (breaking) break;
                        }
                        if (breaking) break;
                    }
                    current_story = null;
                    current_para = -1;
                    current_item = saved_item;
                    breaking = false;
                    break;
                case "set-item":
                    if (current_item == null) throw new MacroError.FAILED (_("Line %d: there is no current object; use for-each-item").printf (c.line));
                    set_item_prop (pub, current_item, c.arg (0), c.arg (1), c.line);
                    break;
                case "set-paragraph":
                    var paras = current_paragraphs ();
                    if (paras == null || current_para < 0 || current_para >= paras.size) throw new MacroError.FAILED (_("Line %d: there is no current paragraph; use for-each-paragraph").printf (c.line));
                    var para = paras[current_para];
                    switch (c.arg (0)) {
                        case "style":
                            if (pub.styles.find_paragraph (c.arg (1)) == null) throw new MacroError.FAILED (_("Line %d: there is no paragraph style \"%s\"").printf (c.line, c.arg (1)));
                            para.style = c.arg (1);
                            break;
                        case "align":
                            para.fmt.align = align_of (c.arg (1));
                            break;
                        case "text":
                            var np = new Paragraph.with_text (c.arg (1), para.style);
                            np.fmt = para.fmt;
                            paras[current_para] = np;
                            break;
                        default:
                            throw new MacroError.FAILED (_("Line %d: paragraphs have no property \"%s\"").printf (c.line, c.arg (0)));
                    }
                    break;
                case "define-style":
                    define_style (pub, c);
                    break;
                case "add-text-frame":
                    var tf = pub.add_text_frame (page_list (pub), Units.parse_num (c.arg (0), 36), Units.parse_num (c.arg (1), 36), Units.parse_num (c.arg (2), 200), Units.parse_num (c.arg (3), 100));
                    var tst = pub.story (tf.story);
                    tst.paras.clear ();
                    foreach (string l in c.arg (4).split ("\n")) tst.paras.add (new Paragraph.with_text (l, c.args.size > 5 ? c.arg (5) : StyleSheet.BASIC));
                    current_item = tf;
                    break;
                case "add-shape":
                    var sh = new ShapeItem (ShapeKind.parse (c.arg (0)));
                    sh.id = pub.next_id ();
                    sh.layer = pub.default_layer ().id;
                    sh.x = Units.parse_num (c.arg (1), 36);
                    sh.y = Units.parse_num (c.arg (2), 36);
                    sh.w = Units.parse_num (c.arg (3), 100);
                    sh.h = Units.parse_num (c.arg (4), 100);
                    sh.fill = new Fill.solid (color_spec (c.arg (5, "Cyan")));
                    page_list (pub).add (sh);
                    current_item = sh;
                    break;
                case "delete-item":
                    if (current_item == null) throw new MacroError.FAILED (_("Line %d: there is no current object").printf (c.line));
                    foreach (var pg in pub.pages) pg.items.remove (current_item);
                    var dt = current_item as TextFrame;
                    if (dt != null && pub.stories.has_key (dt.story)) {
                        pub.stories[dt.story].frames.remove (dt.id);
                        if (pub.stories[dt.story].frames.size == 0) pub.stories.unset (dt.story);
                    }
                    current_item = null;
                    break;
            }
        }

        public static string library_path () {
            return Path.build_filename (Environment.get_user_data_dir (), "singularity", "publish", "macros.ini");
        }

        public static Gee.ArrayList<MacroDef> library () {
            var l = new Gee.ArrayList<MacroDef> ();
            var kf = new KeyFile ();
            try {
                kf.load_from_file (library_path (), KeyFileFlags.NONE);
                foreach (string g in kf.get_groups ()) l.add (new MacroDef (g, kf.get_string (g, "script")));
            } catch (Error e) {
            }
            return l;
        }

        public static void save_to_library (MacroDef m) throws Error {
            var kf = new KeyFile ();
            try {
                kf.load_from_file (library_path (), KeyFileFlags.NONE);
            } catch (Error e) {
            }
            kf.set_string (m.name, "script", m.script);
            DirUtils.create_with_parents (Path.get_dirname (library_path ()), 0700);
            kf.save_to_file (library_path ());
        }

        public static void remove_from_library (string name) throws Error {
            var kf = new KeyFile ();
            kf.load_from_file (library_path (), KeyFileFlags.NONE);
            if (kf.has_group (name)) kf.remove_group (name);
            kf.save_to_file (library_path ());
        }
    }

    public class MacroExpr {
        private MacroEngine engine;
        private string src;
        private int pos = 0;
        private int line;

        public MacroExpr (MacroEngine engine, string src, int line) {
            this.engine = engine;
            this.src = src;
            this.line = line;
        }

        private void skip () {
            while (pos < src.length && (src[pos] == ' ' || src[pos] == '\t')) pos++;
        }

        private bool take (string t) {
            skip ();
            if (src.substring (pos).has_prefix (t)) {
                if (t[0].isalpha () && pos + t.length < src.length && (src[pos + t.length].isalnum () || src[pos + t.length] == '_')) return false;
                pos += t.length;
                return true;
            }
            return false;
        }

        private MacroError err (string msg) {
            return new MacroError.SYNTAX (_("Line %d: %s").printf (line, msg));
        }

        public MacroValue parse () throws Error {
            var v = or_expr ();
            skip ();
            if (pos < src.length) throw err (_("unexpected \"%s\"").printf (src.substring (pos)));
            return v;
        }

        private MacroValue or_expr () throws Error {
            var a = and_expr ();
            while (take ("or")) {
                var b = and_expr ();
                a = new MacroValue.flag (a.truthy () || b.truthy ());
            }
            return a;
        }

        private MacroValue and_expr () throws Error {
            var a = not_expr ();
            while (take ("and")) {
                var b = not_expr ();
                a = new MacroValue.flag (a.truthy () && b.truthy ());
            }
            return a;
        }

        private MacroValue not_expr () throws Error {
            if (take ("not")) return new MacroValue.flag (!not_expr ().truthy ());
            return compare ();
        }

        private MacroValue compare () throws Error {
            var a = sum ();
            string[] ops = { "==", "!=", "<=", ">=", "<", ">" };
            foreach (string op in ops) {
                if (take (op)) {
                    var b = sum ();
                    bool numeric = a.is_num || b.is_num;
                    int c;
                    if (numeric) {
                        double x = a.to_num (), y = b.to_num ();
                        c = x < y ? -1 : (x > y ? 1 : 0);
                    } else {
                        c = strcmp (a.str, b.str);
                    }
                    switch (op) {
                        case "==": return new MacroValue.flag (c == 0);
                        case "!=": return new MacroValue.flag (c != 0);
                        case "<=": return new MacroValue.flag (c <= 0);
                        case ">=": return new MacroValue.flag (c >= 0);
                        case "<": return new MacroValue.flag (c < 0);
                        default: return new MacroValue.flag (c > 0);
                    }
                }
            }
            return a;
        }

        private MacroValue sum () throws Error {
            var a = product ();
            while (true) {
                if (take ("+")) {
                    var b = product ();
                    if (a.is_num && b.is_num) a = new MacroValue.number (a.num + b.num);
                    else a = new MacroValue.text (a.to_string () + b.to_string ());
                } else if (take ("-")) {
                    var b = product ();
                    a = new MacroValue.number (a.to_num () - b.to_num ());
                } else {
                    return a;
                }
            }
        }

        private MacroValue product () throws Error {
            var a = unary ();
            while (true) {
                if (take ("*")) {
                    a = new MacroValue.number (a.to_num () * unary ().to_num ());
                } else if (take ("/")) {
                    double d = unary ().to_num ();
                    if (d == 0) throw new MacroError.FAILED (_("Line %d: division by zero").printf (line));
                    a = new MacroValue.number (a.to_num () / d);
                } else if (take ("%")) {
                    double d = unary ().to_num ();
                    if (d == 0) throw new MacroError.FAILED (_("Line %d: division by zero").printf (line));
                    a = new MacroValue.number (a.to_num () % d);
                } else {
                    return a;
                }
            }
        }

        private MacroValue unary () throws Error {
            if (take ("-")) return new MacroValue.number (-unary ().to_num ());
            return primary ();
        }

        private MacroValue primary () throws Error {
            skip ();
            if (pos >= src.length) throw err (_("a value is missing"));
            char ch = src[pos];
            if (take ("(")) {
                var v = or_expr ();
                if (!take (")")) throw err (_("\")\" is missing"));
                return v;
            }
            if (ch == '"' || ch == '\'') {
                pos++;
                var sb = new StringBuilder ();
                while (pos < src.length && src[pos] != ch) {
                    if (src[pos] == '\\' && pos + 1 < src.length) {
                        pos++;
                        sb.append_c (src[pos] == 'n' ? '\n' : src[pos]);
                    } else {
                        sb.append_c (src[pos]);
                    }
                    pos++;
                }
                if (pos >= src.length) throw err (_("unclosed quotation mark"));
                pos++;
                return new MacroValue.text (sb.str);
            }
            if (ch.isdigit () || (ch == '.' && pos + 1 < src.length && src[pos + 1].isdigit ())) {
                int start = pos;
                while (pos < src.length && (src[pos].isdigit () || src[pos] == '.')) pos++;
                return new MacroValue.number (double.parse (src.substring (start, pos - start)));
            }
            if (ch == '$') pos++;
            if (pos < src.length && (src[pos].isalpha () || src[pos] == '_')) {
                int start = pos;
                while (pos < src.length && (src[pos].isalnum () || src[pos] == '_' || src[pos] == '.' || src[pos] == '-')) pos++;
                string name = src.substring (start, pos - start);
                if (take ("(")) {
                    var args = new Gee.ArrayList<MacroValue> ();
                    if (!take (")")) {
                        do {
                            args.add (or_expr ());
                        } while (take (","));
                        if (!take (")")) throw err (_("\")\" is missing"));
                    }
                    return engine.call (name, args, line);
                }
                return engine.resolve (name, line);
            }
            throw err (_("unexpected \"%s\"").printf (src.substring (pos)));
        }
    }
}
