namespace Singularity.Apps.Publish {

    public class Layer {
        public int id;
        public string name;
        public bool visible = true;
        public bool locked = false;
        public bool printable = true;
        public string color = "#4a86e8";

        public Layer (int id, string name) {
            this.id = id;
            this.name = name;
        }

        public Layer clone () {
            var l = new Layer (id, name);
            l.visible = visible;
            l.locked = locked;
            l.printable = printable;
            l.color = color;
            return l;
        }
    }

    public class Guide {
        public bool vertical;
        public double pos;

        public Guide (bool vertical, double pos) {
            this.vertical = vertical;
            this.pos = pos;
        }

        public Guide clone () {
            return new Guide (vertical, pos);
        }
    }

    public enum NumberStyle {
        ARABIC,
        ROMAN_LOWER,
        ROMAN_UPPER,
        ALPHA_LOWER,
        ALPHA_UPPER;

        public string to_string () {
            switch (this) {
                case ROMAN_LOWER: return "roman";
                case ROMAN_UPPER: return "ROMAN";
                case ALPHA_LOWER: return "alpha";
                case ALPHA_UPPER: return "ALPHA";
                default: return "arabic";
            }
        }

        public static NumberStyle parse (string s) {
            switch (s) {
                case "roman": return ROMAN_LOWER;
                case "ROMAN": return ROMAN_UPPER;
                case "alpha": return ALPHA_LOWER;
                case "ALPHA": return ALPHA_UPPER;
                default: return ARABIC;
            }
        }

        public string label () {
            switch (this) {
                case ROMAN_LOWER: return "i, ii, iii";
                case ROMAN_UPPER: return "I, II, III";
                case ALPHA_LOWER: return "a, b, c";
                case ALPHA_UPPER: return "A, B, C";
                default: return "1, 2, 3";
            }
        }

        public string format (int n) {
            switch (this) {
                case ROMAN_LOWER: return NumberFormat.roman (n).down ();
                case ROMAN_UPPER: return NumberFormat.roman (n);
                case ALPHA_LOWER: return NumberFormat.alpha (n).down ();
                case ALPHA_UPPER: return NumberFormat.alpha (n);
                default: return n.to_string ();
            }
        }
    }

    public class NumberFormat {
        public static string roman (int n) {
            if (n <= 0 || n >= 4000) return n.to_string ();
            int[] vals = { 1000, 900, 500, 400, 100, 90, 50, 40, 10, 9, 5, 4, 1 };
            string[] syms = { "M", "CM", "D", "CD", "C", "XC", "L", "XL", "X", "IX", "V", "IV", "I" };
            var sb = new StringBuilder ();
            for (int i = 0; i < vals.length; i++) {
                while (n >= vals[i]) {
                    sb.append (syms[i]);
                    n -= vals[i];
                }
            }
            return sb.str;
        }

        public static string alpha (int n) {
            if (n <= 0) return n.to_string ();
            var sb = new StringBuilder ();
            while (n > 0) {
                n--;
                sb.prepend_c ((char) ('A' + n % 26));
                n /= 26;
            }
            return sb.str;
        }
    }

    public class Section {
        public int start_page;
        public string prefix = "";
        public string name = "";
        public NumberStyle style = NumberStyle.ARABIC;
        public int start_number = 1;
        public bool continue_numbering = false;

        public Section (int start_page) {
            this.start_page = start_page;
        }

        public Section clone () {
            var s = new Section (start_page);
            s.prefix = prefix;
            s.name = name;
            s.style = style;
            s.start_number = start_number;
            s.continue_numbering = continue_numbering;
            return s;
        }
    }

    public class MasterPage {
        public string id;
        public string name;
        public string based_on = "";
        public Gee.ArrayList<Item> items = new Gee.ArrayList<Item> ();
        public Gee.ArrayList<Item> left_items = new Gee.ArrayList<Item> ();
        public Gee.ArrayList<Guide> guides = new Gee.ArrayList<Guide> ();

        public MasterPage (string id, string name) {
            this.id = id;
            this.name = name;
        }

        public string display_name () {
            return "%s-%s".printf (id, name);
        }

        public MasterPage clone () {
            var m = new MasterPage (id, name);
            m.based_on = based_on;
            foreach (var i in items) m.items.add (i.clone ());
            foreach (var i in left_items) m.left_items.add (i.clone ());
            foreach (var g in guides) m.guides.add (g.clone ());
            return m;
        }

        public Gee.ArrayList<Item> items_for (bool left) {
            return left ? left_items : items;
        }
    }

    public class Page {
        public int id;
        public string master = "A";
        public Gee.ArrayList<Item> items = new Gee.ArrayList<Item> ();
        public Gee.ArrayList<Guide> guides = new Gee.ArrayList<Guide> ();
        public Gee.HashSet<int> overridden = new Gee.HashSet<int> ();
        public bool hide_master = false;
        public double width = double.NAN;
        public double height = double.NAN;
        public bool join_prev = false;
        public string transition = "";
        public string layout_name = "";
        public double transition_duration = 1;

        public Page (int id) {
            this.id = id;
        }

        public Page clone () {
            var p = new Page (id);
            p.master = master;
            p.hide_master = hide_master;
            p.width = width;
            p.height = height;
            p.join_prev = join_prev;
            p.transition = transition;
            p.layout_name = layout_name;
            p.transition_duration = transition_duration;
            foreach (var i in items) p.items.add (i.clone ());
            foreach (var g in guides) p.guides.add (g.clone ());
            p.overridden.add_all (overridden);
            return p;
        }
    }

    public class DocSettings {
        public double width = 210 * Units.PT_PER_MM;
        public double height = 297 * Units.PT_PER_MM;
        public bool facing = false;
        public bool start_left = false;
        public double margin_top = 36;
        public double margin_bottom = 36;
        public double margin_inside = 36;
        public double margin_outside = 36;
        public int columns = 1;
        public double gutter = 12;
        public double bleed_top = 0;
        public double bleed_bottom = 0;
        public double bleed_inside = 0;
        public double bleed_outside = 0;
        public double slug = 0;
        public double baseline_start = 36;
        public double baseline_step = 14;
        public string units = "mm";
        public bool cmyk = true;
        public string page_size = "a4";
        public string impose = "";
        public string icc_profile = "";
        public int intent = 1;
        public bool overprint_black = true;
        public bool proof = false;

        public DocSettings clone () {
            var s = new DocSettings ();
            s.width = width;
            s.height = height;
            s.facing = facing;
            s.start_left = start_left;
            s.margin_top = margin_top;
            s.margin_bottom = margin_bottom;
            s.margin_inside = margin_inside;
            s.margin_outside = margin_outside;
            s.columns = columns;
            s.gutter = gutter;
            s.bleed_top = bleed_top;
            s.bleed_bottom = bleed_bottom;
            s.bleed_inside = bleed_inside;
            s.bleed_outside = bleed_outside;
            s.slug = slug;
            s.baseline_start = baseline_start;
            s.baseline_step = baseline_step;
            s.units = units;
            s.cmyk = cmyk;
            s.page_size = page_size;
            s.impose = impose;
            s.icc_profile = icc_profile;
            s.intent = intent;
            s.overprint_black = overprint_black;
            s.proof = proof;
            return s;
        }

        public void set_bleed (double b) {
            bleed_top = bleed_bottom = bleed_inside = bleed_outside = b;
        }

        public void set_margins (double m) {
            margin_top = margin_bottom = margin_inside = margin_outside = m;
        }

        public bool landscape () {
            return width > height;
        }

        public double max_bleed () {
            return double.max (double.max (bleed_top, bleed_bottom), double.max (bleed_inside, bleed_outside));
        }
    }

    public class MergeSettings {
        public string source_kind = "";
        public string source_path = "";
        public Gee.ArrayList<string> fields = new Gee.ArrayList<string> ();
        public Gee.ArrayList<Gee.ArrayList<string>> records = new Gee.ArrayList<Gee.ArrayList<string>> ();
        public int preview = -1;
        public bool catalogue = false;
        public int cat_rows = 2;
        public int cat_cols = 2;
        public double cat_x = 36;
        public double cat_y = 36;
        public double cat_w = 200;
        public double cat_h = 200;
        public double cat_gap_x = 0;
        public double cat_gap_y = 0;
        public Gee.HashSet<int> excluded = new Gee.HashSet<int> ();
        public Gee.ArrayList<MergeFilter> filters = new Gee.ArrayList<MergeFilter> ();
        public Gee.ArrayList<MergeSort> sorts = new Gee.ArrayList<MergeSort> ();
        public string email_field = "";
        public string email_subject = "";
        public bool remove_blank_lines = true;
        public int image_fit = -1;
        public bool hide_missing_images = false;

        public MergeSettings clone () {
            var m = new MergeSettings ();
            m.source_kind = source_kind;
            m.source_path = source_path;
            m.fields.add_all (fields);
            foreach (var r in records) {
                var nr = new Gee.ArrayList<string> ();
                nr.add_all (r);
                m.records.add (nr);
            }
            m.preview = preview;
            m.catalogue = catalogue;
            m.remove_blank_lines = remove_blank_lines;
            m.image_fit = image_fit;
            m.hide_missing_images = hide_missing_images;
            m.cat_rows = cat_rows;
            m.cat_cols = cat_cols;
            m.cat_x = cat_x;
            m.cat_y = cat_y;
            m.cat_w = cat_w;
            m.cat_h = cat_h;
            m.cat_gap_x = cat_gap_x;
            m.cat_gap_y = cat_gap_y;
            m.excluded.add_all (excluded);
            foreach (var f in filters) m.filters.add (f.clone ());
            foreach (var o in sorts) m.sorts.add (o.clone ());
            m.email_field = email_field;
            m.email_subject = email_subject;
            return m;
        }

        public bool passes_filters (int record) {
            if (filters.size == 0) return true;
            bool result = true;
            for (int i = 0; i < filters.size; i++) {
                var f = filters[i];
                bool m = f.matches (value (record, f.field));
                if (i == 0) result = m;
                else if (f.or_previous) result = result || m;
                else result = result && m;
            }
            return result;
        }

        public Gee.ArrayList<int> selected_records () {
            var list = new Gee.ArrayList<int> ();
            for (int i = 0; i < records.size; i++) if (!excluded.contains (i) && passes_filters (i)) list.add (i);
            if (sorts.size > 0) {
                list.sort ((a, b) => {
                    foreach (var o in sorts) {
                        string va = value (a, o.field), vb = value (b, o.field);
                        double x = 0, y = 0;
                        int c;
                        if (double.try_parse (va.strip (), out x) && double.try_parse (vb.strip (), out y) && va.strip () != "" && vb.strip () != "") c = x < y ? -1 : (x > y ? 1 : 0);
                        else c = va.collate (vb);
                        if (c != 0) return o.descending ? -c : c;
                    }
                    return a - b;
                });
            }
            return list;
        }

        public bool active () {
            return fields.size > 0;
        }

        public string value (int record, string field) {
            int fi = fields.index_of (field);
            if (fi < 0 || record < 0 || record >= records.size) return "";
            var r = records[record];
            return fi < r.size ? r[fi] : "";
        }

        public Rect area () {
            return Rect (cat_x, cat_y, cat_w, cat_h);
        }
    }

    public class Metadata {
        public string title = "";
        public string author = "";
        public string subject = "";
        public string keywords = "";
        public string created = "";
        public string modified = "";

        public Metadata clone () {
            var m = new Metadata ();
            m.title = title;
            m.author = author;
            m.subject = subject;
            m.keywords = keywords;
            m.created = created;
            m.modified = modified;
            return m;
        }
    }

    public class Spread {
        public Gee.ArrayList<int> pages = new Gee.ArrayList<int> ();
        public bool first_is_left = false;
    }

    public class ItemRef {
        public Item item;
        public Page? page;
        public MasterPage? master;
        public Gee.ArrayList<Item> list;
        public GroupItem? group;

        public ItemRef (Item item, Page? page, MasterPage? master, Gee.ArrayList<Item> list, GroupItem? group) {
            this.item = item;
            this.page = page;
            this.master = master;
            this.list = list;
            this.group = group;
        }
    }

    public class Publication {
        public DocSettings settings = new DocSettings ();
        public Metadata meta = new Metadata ();
        public Gee.ArrayList<Layer> layers = new Gee.ArrayList<Layer> ();
        public Gee.ArrayList<MasterPage> masters = new Gee.ArrayList<MasterPage> ();
        public Gee.ArrayList<Page> pages = new Gee.ArrayList<Page> ();
        public Gee.HashMap<int, Story> stories = new Gee.HashMap<int, Story> ();
        public StyleSheet styles = StyleSheet.standard ();
        public Gee.ArrayList<Swatch> swatches = new Gee.ArrayList<Swatch> ();
        public Gee.HashMap<string, Bytes> media = new Gee.HashMap<string, Bytes> ();
        public Gee.ArrayList<Section> sections = new Gee.ArrayList<Section> ();
        public MergeSettings merge = new MergeSettings ();
        public Gee.ArrayList<Bookmark> bookmarks = new Gee.ArrayList<Bookmark> ();
        public BusinessInfo business = new BusinessInfo ();
        public string color_scheme = "";
        public string font_scheme = "";
        public Gee.ArrayList<MacroDef> macros = new Gee.ArrayList<MacroDef> ();
        public Gee.TreeMap<string, string> hyph_exceptions = new Gee.TreeMap<string, string> ();
        public Gee.ArrayList<TextVariable> text_vars = new Gee.ArrayList<TextVariable> ();
        public Gee.ArrayList<ObjectStyle> object_styles = new Gee.ArrayList<ObjectStyle> ();
        public Gee.ArrayList<PreflightProfile> preflight_profiles = new Gee.ArrayList<PreflightProfile> ();
        public string preflight_profile = "";
        public TocSettings? toc = null;
        public FootnoteOptions footnotes = new FootnoteOptions ();
        public int endnote_story = 0;
        public string xml_map = "";
        public Gee.ArrayList<ReviewComment> comments = new Gee.ArrayList<ReviewComment> ();
        public Gee.ArrayList<TextCondition> conditions = new Gee.ArrayList<TextCondition> ();
        public Gee.ArrayList<ConditionSet> condition_sets = new Gee.ArrayList<ConditionSet> ();
        public string active_condition_set = "";
        public Gee.ArrayList<TableStyle> table_styles = new Gee.ArrayList<TableStyle> ();
        public Gee.ArrayList<CellStyle> cell_styles = new Gee.ArrayList<CellStyle> ();
        public IndexSettings? index = null;

        public ObjectStyle? object_style (string name) {
            foreach (var o in object_styles) if (o.name == name) return o;
            return null;
        }
        public string file_name = "";
        public int chapter_number = 1;

        public TextVariable? text_var (string name) {
            foreach (var v in text_vars) if (v.name == name) return v;
            return null;
        }
        public ColorOutput? output = null;
        public int id_counter = 1;
        public string base_dir = "";

        public Publication () {
        }

        public static Publication create (DocSettings? s = null, int page_count = 1) {
            var p = new Publication ();
            if (s != null) p.settings = s;
            p.layers.add (new Layer (p.next_id (), _("Layer 1")));
            p.masters.add (new MasterPage ("A", _("Master")));
            p.swatches.add_all (standard_swatches ());
            p.sections.add (new Section (0));
            for (int i = 0; i < page_count; i++) p.add_page (-1, "A");
            return p;
        }

        public static Gee.ArrayList<Swatch> standard_swatches () {
            var l = new Gee.ArrayList<Swatch> ();
            l.add (new Swatch.cmyk ("Paper", 0, 0, 0, 0));
            l.add (new Swatch.cmyk ("Black", 0, 0, 0, 1));
            var reg = new Swatch.cmyk ("Registration", 1, 1, 1, 1);
            l.add (reg);
            l.add (new Swatch.cmyk ("Cyan", 1, 0, 0, 0));
            l.add (new Swatch.cmyk ("Magenta", 0, 1, 0, 0));
            l.add (new Swatch.cmyk ("Yellow", 0, 0, 1, 0));
            l.add (new Swatch.cmyk ("Red", 0, 1, 1, 0));
            l.add (new Swatch.cmyk ("Green", 1, 0, 1, 0));
            l.add (new Swatch.cmyk ("Blue", 1, 1, 0, 0));
            l.add (new Swatch.cmyk (StyleSheet.HYPERLINK, 1, 0.7, 0, 0.05));
            return l;
        }

        public int next_id () {
            return id_counter++;
        }

        public Publication clone () {
            var p = new Publication ();
            p.settings = settings.clone ();
            p.meta = meta.clone ();
            foreach (var l in layers) p.layers.add (l.clone ());
            foreach (var m in masters) p.masters.add (m.clone ());
            foreach (var pg in pages) p.pages.add (pg.clone ());
            foreach (var e in stories.entries) p.stories[e.key] = e.value.clone ();
            p.styles = styles.clone ();
            foreach (var s in swatches) p.swatches.add (s.clone ());
            foreach (var e in media.entries) p.media[e.key] = e.value;
            foreach (var s in sections) p.sections.add (s.clone ());
            p.merge = merge.clone ();
            foreach (var b in bookmarks) p.bookmarks.add (b.clone ());
            p.business = business.clone ();
            p.color_scheme = color_scheme;
            p.font_scheme = font_scheme;
            foreach (var m in macros) p.macros.add (m.clone ());
            foreach (var e in hyph_exceptions.entries) p.hyph_exceptions[e.key] = e.value;
            foreach (var v in text_vars) p.text_vars.add (v.clone ());
            foreach (var o in object_styles) p.object_styles.add (o.clone ());
            foreach (var pp in preflight_profiles) p.preflight_profiles.add (pp.clone ());
            p.preflight_profile = preflight_profile;
            p.footnotes = footnotes.clone ();
            p.endnote_story = endnote_story;
            p.xml_map = xml_map;
            foreach (var c in comments) p.comments.add (c.clone ());
            foreach (var c in conditions) p.conditions.add (c.clone ());
            foreach (var c in condition_sets) p.condition_sets.add (c.clone ());
            p.active_condition_set = active_condition_set;
            foreach (var ts in table_styles) p.table_styles.add (ts.clone ());
            foreach (var cs in cell_styles) p.cell_styles.add (cs.clone ());
            p.index = index != null ? index.clone () : null;
            if (toc != null) p.toc = toc.clone ();
            p.file_name = file_name;
            p.chapter_number = chapter_number;
            p.id_counter = id_counter;
            p.base_dir = base_dir;
            return p;
        }

        public Page add_page (int at, string master) {
            var pg = new Page (next_id ());
            pg.master = master;
            if (at < 0 || at > pages.size) pages.add (pg);
            else {
                pages.insert (at, pg);
                foreach (var s in sections) if (s.start_page >= at && s.start_page > 0) s.start_page++;
                foreach (var b in bookmarks) if (b.page >= at) b.page++;
            }
            return pg;
        }

        public void remove_page (int index) {
            if (index < 0 || index >= pages.size || pages.size <= 1) return;
            var dead_marks = new Gee.ArrayList<Bookmark> ();
            foreach (var b in bookmarks) {
                if (b.page == index) dead_marks.add (b);
                else if (b.page > index) b.page--;
            }
            bookmarks.remove_all (dead_marks);
            var pg = pages[index];
            foreach (var it in pg.items) forget_item (it);
            pages.remove_at (index);
            var drop = new Gee.ArrayList<Section> ();
            foreach (var s in sections) {
                if (s.start_page == index && index > 0) drop.add (s);
                else if (s.start_page > index) s.start_page--;
            }
            sections.remove_all (drop);
            prune_stories ();
        }

        public void move_page (int from, int to) {
            if (from < 0 || from >= pages.size) return;
            var pg = pages.remove_at (from);
            to = to.clamp (0, pages.size);
            pages.insert (to, pg);
            foreach (var b in bookmarks) {
                if (b.page == from) b.page = to;
                else if (from < to && b.page > from && b.page <= to) b.page--;
                else if (from > to && b.page >= to && b.page < from) b.page++;
            }
        }

        private void forget_item (Item it) {
            var t = it as TextFrame;
            if (t != null && stories.has_key (t.story)) stories[t.story].frames.remove (t.id);
            var g = it as GroupItem;
            if (g != null) foreach (var c in g.children) forget_item (c);
        }

        public void prune_stories () {
            var used = new Gee.HashSet<int> ();
            foreach (var r in all_items ()) {
                var t = r.item as TextFrame;
                if (t != null) used.add (t.story);
            }
            var dead = new Gee.ArrayList<int> ();
            foreach (var k in stories.keys) if (!used.contains (k)) dead.add (k);
            foreach (var k in dead) stories.unset (k);
            foreach (var s in stories.values) {
                var keep = new Gee.ArrayList<int> ();
                foreach (int fid in s.frames) {
                    var r = find_item (fid);
                    if (r != null && r.item is TextFrame && ((TextFrame) r.item).story == s.id && !keep.contains (fid)) keep.add (fid);
                }
                s.frames = keep;
            }
        }

        public Layer? layer (int id) {
            foreach (var l in layers) if (l.id == id) return l;
            return null;
        }

        public int layer_index (int id) {
            for (int i = 0; i < layers.size; i++) if (layers[i].id == id) return i;
            return 0;
        }

        public Layer default_layer () {
            foreach (var l in layers) if (l.visible && !l.locked) return l;
            return layers[0];
        }

        public MasterPage? master (string id) {
            foreach (var m in masters) if (m.id == id) return m;
            return null;
        }

        public string next_master_id () {
            for (int i = 0; i < 26 * 27; i++) {
                string id = NumberFormat.alpha (i + 1);
                if (master (id) == null) return id;
            }
            return "M%d".printf (masters.size + 1);
        }

        public Gee.ArrayList<MasterPage> master_chain (string id) {
            var chain = new Gee.ArrayList<MasterPage> ();
            string cur = id;
            int guard = 0;
            while (cur != "" && guard++ < 16) {
                var m = master (cur);
                if (m == null || chain.contains (m)) break;
                chain.insert (0, m);
                cur = m.based_on;
            }
            return chain;
        }

        public bool joined (int index) {
            return index > 0 && index < pages.size && pages[index].join_prev;
        }

        public bool is_left_page (int index) {
            if (!settings.facing) return false;
            if (joined (index)) return false;
            int n = settings.start_left ? 0 : 1;
            for (int i = 0; i < index && i < pages.size; i++) if (!joined (i)) n++;
            return n % 2 == 0;
        }

        public double page_w (int index) {
            if (index >= 0 && index < pages.size && !pages[index].width.is_nan ()) return pages[index].width;
            return settings.width;
        }

        public double page_h (int index) {
            if (index >= 0 && index < pages.size && !pages[index].height.is_nan ()) return pages[index].height;
            return settings.height;
        }

        public Gee.ArrayList<Spread> spreads () {
            var list = new Gee.ArrayList<Spread> ();
            if (!settings.facing) {
                Spread? prev = null;
                for (int i = 0; i < pages.size; i++) {
                    if (joined (i) && prev != null) {
                        prev.pages.add (i);
                        continue;
                    }
                    var s = new Spread ();
                    s.pages.add (i);
                    list.add (s);
                    prev = s;
                }
                return list;
            }
            Spread? cur = null;
            Spread? last = null;
            for (int i = 0; i < pages.size; i++) {
                if (joined (i) && last != null) {
                    last.pages.add (i);
                    continue;
                }
                bool left = is_left_page (i);
                if (left || cur == null) {
                    cur = new Spread ();
                    cur.first_is_left = left;
                    list.add (cur);
                }
                cur.pages.add (i);
                last = cur;
                if (!left) cur = null;
            }
            return list;
        }

        public int spread_of (int page_index) {
            var sp = spreads ();
            for (int i = 0; i < sp.size; i++) if (sp[i].pages.contains (page_index)) return i;
            return 0;
        }

        public Section section_for (int page_index) {
            Section best = sections.size > 0 ? sections[0] : new Section (0);
            foreach (var s in sections) if (s.start_page <= page_index && s.start_page >= best.start_page) best = s;
            return best;
        }

        public Section? section_starting (int page_index) {
            Section? found = null;
            foreach (var s in sections) if (s.start_page == page_index) found = s;
            return found;
        }

        public int page_number (int page_index) {
            int number = 1;
            for (int i = 0; i <= page_index; i++) {
                if (i > 0) number++;
                var s = section_starting (i);
                if (s != null && (i == 0 || !s.continue_numbering)) number = s.start_number;
            }
            return number;
        }

        public string page_label (int page_index) {
            if (page_index < 0) return "";
            var s = section_for (page_index);
            return s.prefix + s.style.format (page_number (page_index));
        }

        public Story story (int id) {
            if (!stories.has_key (id)) {
                var s = new Story (id);
                stories[id] = s;
            }
            return stories[id];
        }

        public Story new_story () {
            var s = new Story (next_id ());
            stories[s.id] = s;
            return s;
        }

        public TextFrame add_text_frame (Gee.ArrayList<Item> list, double x, double y, double w, double h, Story? story = null) {
            var t = new TextFrame ();
            t.id = next_id ();
            t.x = x;
            t.y = y;
            t.w = w;
            t.h = h;
            t.layer = default_layer ().id;
            var s = story ?? new_story ();
            t.story = s.id;
            s.frames.add (t.id);
            list.add (t);
            return t;
        }

        public Gee.ArrayList<TextFrame> thread_frames (int story_id) {
            var list = new Gee.ArrayList<TextFrame> ();
            if (!stories.has_key (story_id)) return list;
            foreach (int fid in stories[story_id].frames) {
                var r = find_item (fid);
                if (r != null && r.item is TextFrame) list.add ((TextFrame) r.item);
            }
            return list;
        }

        public void link_frames (TextFrame from, TextFrame to) {
            if (from.id == to.id || from.story == to.story) return;
            var src = story (from.story);
            var dst = story (to.story);
            if (!dst.is_empty ()) {
                var end = src.end_pos ();
                if (!src.is_empty ()) end = src.split_paragraph (end);
                src.insert_story (end, dst);
                if (src.paras.size > 1 && src.paras[src.paras.size - 1].length () == 0 && dst.paras.size > 0 && dst.paras[dst.paras.size - 1].length () != 0) src.paras.remove_at (src.paras.size - 1);
            }
            var moving = new Gee.ArrayList<int> ();
            moving.add_all (dst.frames);
            if (!moving.contains (to.id)) moving.insert (0, to.id);
            int at = src.frames.index_of (from.id) + 1;
            foreach (int fid in moving) {
                var r = find_item (fid);
                if (r == null || !(r.item is TextFrame)) continue;
                ((TextFrame) r.item).story = src.id;
                src.frames.remove (fid);
                src.frames.insert (at.clamp (0, src.frames.size), fid);
                at++;
            }
            stories.unset (dst.id);
        }

        public void unlink_after (TextFrame frame) {
            var s = story (frame.story);
            int idx = s.frames.index_of (frame.id);
            if (idx < 0 || idx >= s.frames.size - 1) return;
            var ns = new_story ();
            ns.paras.clear ();
            ns.paras.add (new Paragraph.with_text (""));
            while (s.frames.size > idx + 1) {
                int fid = s.frames.remove_at (idx + 1);
                ns.frames.add (fid);
                var r = find_item (fid);
                if (r != null && r.item is TextFrame) ((TextFrame) r.item).story = ns.id;
            }
        }

        public void detach_frame (TextFrame frame) {
            var s = story (frame.story);
            if (s.frames.size <= 1) return;
            s.frames.remove (frame.id);
            var ns = new_story ();
            ns.frames.add (frame.id);
            frame.story = ns.id;
        }

        public delegate bool ItemVisitor (ItemRef r);

        private bool walk_list (Gee.ArrayList<Item> list, Page? page, MasterPage? master, GroupItem? group, ItemVisitor f) {
            foreach (var it in list) {
                if (!f (new ItemRef (it, page, master, list, group))) return false;
                var g = it as GroupItem;
                if (g != null && !walk_list (g.children, page, master, g, f)) return false;
            }
            return true;
        }

        public void walk (ItemVisitor f) {
            foreach (var m in masters) {
                if (!walk_list (m.items, null, m, null, f)) return;
                if (!walk_list (m.left_items, null, m, null, f)) return;
            }
            foreach (var pg in pages) if (!walk_list (pg.items, pg, null, null, f)) return;
        }

        public Gee.ArrayList<ItemRef> all_items () {
            var list = new Gee.ArrayList<ItemRef> ();
            walk ((r) => {
                list.add (r);
                return true;
            });
            return list;
        }

        public ItemRef? find_item (int id) {
            ItemRef? found = null;
            walk ((r) => {
                if (r.item.id == id) {
                    found = r;
                    return false;
                }
                return true;
            });
            if (found == null) found = find_anchored (id);
            return found;
        }

        private static Item? find_in (Item it, int id) {
            if (it.id == id) return it;
            var g = it as GroupItem;
            if (g != null) foreach (var c in g.children) {
                var f = find_in (c, id);
                if (f != null) return f;
            }
            return null;
        }

        public ItemRef? find_anchored (int id) {
            foreach (var st in stories.values) foreach (var p in st.paras) foreach (var r in p.runs) {
                if (r.anchor == null) continue;
                var it = find_in (r.anchor, id);
                if (it != null) return new ItemRef (it, null, null, new Gee.ArrayList<Item> (), null);
            }
            return null;
        }

        public Gee.ArrayList<Item> anchored_items () {
            var list = new Gee.ArrayList<Item> ();
            foreach (var st in stories.values) foreach (var p in st.paras) foreach (var r in p.runs) if (r.anchor != null) list.add (r.anchor);
            return list;
        }

        public int page_index_of (Page? p) {
            if (p == null) return -1;
            return pages.index_of (p);
        }

        public Bookmark? bookmark (string name) {
            foreach (var b in bookmarks) if (b.name == name) return b;
            return null;
        }

        public Swatch? swatch (string name) {
            foreach (var s in swatches) if (s.name == name) return s;
            return null;
        }

        public string unique_swatch_name (string base_name) {
            if (swatch (base_name) == null) return base_name;
            for (int i = 2; ; i++) {
                string n = "%s %d".printf (base_name, i);
                if (swatch (n) == null) return n;
            }
        }

        public string canonical (string spec) {
            if (!ColorRef.is_swatch (spec)) return spec;
            string cur = spec;
            for (int guard = 0; guard < 8; guard++) {
                var sw = swatch (ColorRef.swatch_name (cur));
                if (sw == null || sw.tint_of == "" || sw.tint_of == sw.name) return cur;
                double t = ColorRef.tint_of (cur);
                double combined = (t < 99.99 ? t : 100) * sw.tint / 100;
                cur = ColorRef.swatch (sw.tint_of, combined);
            }
            return cur;
        }

        public Rgba resolve (string raw) {
            string spec = canonical (raw);
            if (output != null) return output.map (this, spec, resolve_screen (spec));
            return resolve_screen (spec);
        }

        private Rgba cmyk_screen (double c, double m, double y, double k) {
            if (settings.proof) return ColorManager.for_settings (settings).cmyk_to_rgb (c, m, y, k);
            return ColorMath.cmyk_to_rgb (c, m, y, k);
        }

        private Rgba rgb_screen (Rgba v) {
            if (!settings.proof) return v;
            var cm = ColorManager.for_settings (settings);
            double c, m, y, k;
            cm.rgb_to_cmyk (v.r, v.g, v.b, out c, out m, out y, out k);
            var o = cm.cmyk_to_rgb (c, m, y, k);
            o.a = v.a;
            return o;
        }

        public Rgba resolve_screen (string raw) {
            if (raw == ColorRef.NONE) return Rgba (0, 0, 0, 0);
            string spec = canonical (raw);
            if (ColorRef.is_swatch (spec)) {
                var sw = swatch (ColorRef.swatch_name (spec));
                if (sw == null) return Rgba (0, 0, 0, 1);
                double t = ColorRef.tint_of (spec);
                if (sw.model == ColorModel.CMYK) {
                    double f = t < 99.99 ? t / 100 : 1;
                    return cmyk_screen (sw.c * f, sw.m * f, sw.y * f, sw.k * f);
                }
                var c = sw.rgba ();
                if (t < 99.99) return rgb_screen (ColorMath.tint (c, t));
                return rgb_screen (c);
            }
            if (spec.has_prefix ("cmyk:")) {
                string[] f = spec.substring (5).split (",");
                if (f.length == 4) return cmyk_screen (Units.parse_num (f[0], 0), Units.parse_num (f[1], 0), Units.parse_num (f[2], 0), Units.parse_num (f[3], 0));
            }
            Rgba c;
            if (Rgba.parse_hex (spec, out c)) return rgb_screen (c);
            return Rgba (0, 0, 0, 1);
        }

        public bool is_rgb_color (string spec) {
            if (spec == ColorRef.NONE) return false;
            if (ColorRef.is_swatch (spec)) {
                var sw = swatch (ColorRef.swatch_name (spec));
                return sw != null && sw.model == ColorModel.RGB;
            }
            return !spec.has_prefix ("cmyk:");
        }

        public Rect page_rect (int page_index = -1) {
            return Rect (0, 0, page_w (page_index), page_h (page_index));
        }

        public Rect bleed_rect (int page_index) {
            var s = settings;
            bool left = is_left_page (page_index);
            double l = s.facing ? (left ? s.bleed_outside : s.bleed_inside) : s.bleed_inside;
            double r = s.facing ? (left ? s.bleed_inside : s.bleed_outside) : s.bleed_outside;
            var sp = spreads ()[spread_of (page_index)];
            if (sp.pages.size > 1) {
                int at = sp.pages.index_of (page_index);
                if (at > 0) l = 0;
                if (at < sp.pages.size - 1) r = 0;
                if (s.facing && left) r = 0;
            }
            return Rect (-l, -s.bleed_top, page_w (page_index) + l + r, page_h (page_index) + s.bleed_top + s.bleed_bottom);
        }

        public Rect margin_rect (int page_index) {
            var s = settings;
            bool left = is_left_page (page_index);
            double ml = s.facing && left ? s.margin_outside : s.margin_inside;
            double mr = s.facing && left ? s.margin_inside : s.margin_outside;
            if (!s.facing) {
                ml = s.margin_inside;
                mr = s.margin_outside;
            }
            return Rect (ml, s.margin_top, page_w (page_index) - ml - mr, page_h (page_index) - s.margin_top - s.margin_bottom);
        }

        public Gee.ArrayList<Rect?> column_rects (int page_index) {
            var list = new Gee.ArrayList<Rect?> ();
            var m = margin_rect (page_index);
            int n = int.max (1, settings.columns);
            double cw = (m.w - settings.gutter * (n - 1)) / n;
            for (int i = 0; i < n; i++) list.add (Rect (m.x + i * (cw + settings.gutter), m.y, cw, m.h));
            return list;
        }

        public Gee.ArrayList<Item> master_items_for (int page_index) {
            var list = new Gee.ArrayList<Item> ();
            if (page_index < 0 || page_index >= pages.size) return list;
            var pg = pages[page_index];
            if (pg.hide_master || pg.master == "") return list;
            bool left = is_left_page (page_index);
            foreach (var m in master_chain (pg.master)) {
                foreach (var it in m.items_for (left && settings.facing)) {
                    if (!pg.overridden.contains (it.id)) list.add (it);
                }
            }
            return list;
        }

        public Item? override_master_item (int page_index, Item master_item) {
            var pg = pages[page_index];
            if (pg.overridden.contains (master_item.id)) return null;
            var copy = master_item.clone ();
            reassign (copy);
            pg.overridden.add (master_item.id);
            pg.items.insert (0, copy);
            return copy;
        }

        public void reassign (Item it) {
            it.id = next_id ();
            var t = it as TextFrame;
            if (t != null) {
                var src = stories.has_key (t.story) ? stories[t.story] : null;
                var ns = src != null ? src.clone () : new Story (0);
                ns.id = next_id ();
                ns.frames.clear ();
                ns.frames.add (t.id);
                stories[ns.id] = ns;
                t.story = ns.id;
            }
            var tb = it as TableItem;
            if (tb != null) foreach (var row in tb.cells) foreach (var c in row) c.story.id = next_id ();
            var g = it as GroupItem;
            if (g != null) foreach (var c in g.children) reassign (c);
        }

        public Gee.ArrayList<string> used_fonts () {
            var set = new Gee.TreeSet<string> ();
            foreach (var st in styles.paragraph) if (st.chars.font != null) set.add (st.chars.font);
            foreach (var st in styles.character) if (st.chars.font != null) set.add (st.chars.font);
            foreach (var s in stories.values) collect_fonts (s, set);
            walk ((r) => {
                var tb = r.item as TableItem;
                if (tb != null) foreach (var row in tb.cells) foreach (var c in row) collect_fonts (c.story, set);
                return true;
            });
            var l = new Gee.ArrayList<string> ();
            l.add_all (set);
            return l;
        }

        private void collect_fonts (Story s, Gee.TreeSet<string> set) {
            foreach (var p in s.paras) {
                var pf = new ParaFormat ();
                var cf = CharFormat.defaults ();
                styles.resolve_paragraph (p.style, pf, cf);
                if (cf.font != null) set.add (cf.font);
                foreach (var r in p.runs) if (r.fmt.font != null) set.add (r.fmt.font);
            }
        }

        public void rename_swatch (string old_name, string new_name) {
            var sw = swatch (old_name);
            if (sw == null) return;
            sw.name = new_name;
            walk ((r) => {
                remap_item_colors (r.item, old_name, new_name);
                return true;
            });
            foreach (var st in styles.paragraph) st.chars.color = remap (st.chars.color, old_name, new_name);
            foreach (var st in styles.character) st.chars.color = remap (st.chars.color, old_name, new_name);
            foreach (var s in stories.values) foreach (var p in s.paras) foreach (var run in p.runs) {
                run.fmt.color = remap (run.fmt.color, old_name, new_name);
                run.fmt.outline_color = remap (run.fmt.outline_color, old_name, new_name);
                run.fmt.glow_color = remap (run.fmt.glow_color, old_name, new_name);
            }
        }

        private static string? remap (string? spec, string old_name, string new_name) {
            if (spec == null || !ColorRef.is_swatch (spec) || ColorRef.swatch_name (spec) != old_name) return spec;
            return ColorRef.swatch (new_name, ColorRef.tint_of (spec));
        }

        private void remap_item_colors (Item it, string o, string n) {
            it.fill.color = remap (it.fill.color, o, n);
            foreach (var st in it.fill.stops) st.color = remap (st.color, o, n);
            it.stroke.color = remap (it.stroke.color, o, n);
            it.shadow.color = remap (it.shadow.color, o, n);
            it.fill.bg_color = remap (it.fill.bg_color, o, n);
            it.effects.glow_color = remap (it.effects.glow_color, o, n);
            it.border_art.color = remap (it.border_art.color, o, n);
            var im = it as ImageFrame;
            if (im != null) im.recolor_color = remap (im.recolor_color, o, n);
            var tb = it as TableItem;
            if (tb != null) {
                tb.border_color = remap (tb.border_color, o, n);
                tb.header_fill = remap (tb.header_fill, o, n);
                tb.alt_fill = remap (tb.alt_fill, o, n);
                foreach (var row in tb.cells) foreach (var c in row) c.fill = remap (c.fill, o, n);
            }
        }

        public bool swatch_in_use (string name) {
            foreach (var t in swatches) if (t.tint_of == name && t.name != name && swatch_in_use (t.name)) return true;
            bool used = false;
            walk ((r) => {
                foreach (string c in r.item.colors ()) if (ColorRef.is_swatch (c) && ColorRef.swatch_name (c) == name) used = true;
                return !used;
            });
            if (used) return true;
            foreach (var st in styles.paragraph) if (st.chars.color != null && ColorRef.swatch_name (st.chars.color) == name) return true;
            foreach (var s in stories.values) foreach (var p in s.paras) foreach (var run in p.runs) if (run.fmt.color != null && ColorRef.swatch_name (run.fmt.color) == name) return true;
            return false;
        }

        public string add_media (uint8[] data, string suggested) {
            string ext = "bin";
            int dot = suggested.last_index_of (".");
            if (dot >= 0) ext = suggested.substring (dot + 1).down ();
            string hash = Checksum.compute_for_data (ChecksumType.SHA1, data).substring (0, 12);
            string key = "%s.%s".printf (hash, ext);
            if (!media.has_key (key)) media[key] = new Bytes (data);
            return key;
        }

        public void prune_media () {
            var used = new Gee.HashSet<string> ();
            walk ((r) => {
                var im = r.item as ImageFrame;
                if (im != null && im.media != "") used.add (im.media);
                return true;
            });
            var dead = new Gee.ArrayList<string> ();
            foreach (var k in media.keys) if (!used.contains (k)) dead.add (k);
            foreach (var k in dead) media.unset (k);
        }
    }
}
