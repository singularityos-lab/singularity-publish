namespace Singularity.Apps.Publish {

    public class TemplateInfo {
        public string id;
        public string name;
        public string category;
        public string description;

        public TemplateInfo (string id, string name, string category, string description) {
            this.id = id;
            this.name = name;
            this.category = category;
            this.description = description;
        }
    }

    public class Templates {
        private const string SANS = "Inter";
        private const string SERIF = "DejaVu Serif";

        public static Gee.ArrayList<TemplateInfo> all () {
            var l = new Gee.ArrayList<TemplateInfo> ();
            l.add (new TemplateInfo ("flyer", _("Flyer"), _("Marketing"), _("A4 event flyer with a full-bleed header")));
            l.add (new TemplateInfo ("brochure", _("Tri-Fold Brochure"), _("Marketing"), _("Landscape A4 folded in three, outside and inside")));
            l.add (new TemplateInfo ("newsletter", _("Newsletter"), _("Publications"), _("Four facing pages with a threaded three-column article")));
            l.add (new TemplateInfo ("business-cards", _("Business Cards"), _("Stationery"), _("Front and back, printed ten to an A4 sheet")));
            l.add (new TemplateInfo ("poster", _("Poster"), _("Marketing"), _("A2 poster for a concert or exhibition")));
            l.add (new TemplateInfo ("greeting-card", _("Folded Greeting Card"), _("Cards"), _("A5 folded to A6, outside and inside")));
            l.add (new TemplateInfo ("menu", _("Menu"), _("Hospitality"), _("A4 restaurant menu with dot leaders to the prices")));
            l.add (new TemplateInfo ("certificate", _("Certificate"), _("Stationery"), _("Landscape certificate with a border and a seal")));
            l.add (new TemplateInfo ("invitation", _("Invitation"), _("Cards"), _("Five by seven inch invitation")));
            l.add (new TemplateInfo ("postcard", _("Postcard"), _("Cards"), _("A6 postcard with a picture front and an address back")));
            l.add (new TemplateInfo ("letterhead", _("Letterhead"), _("Stationery"), _("A4 letterhead with a header, a footer and a letter")));
            l.add (new TemplateInfo ("resume", _("Resume"), _("Personal"), _("Two-column resume with a sidebar")));
            l.add (new TemplateInfo ("program", _("Event Program"), _("Publications"), _("A5 facing program with a schedule table")));
            l.add (new TemplateInfo ("calendar", _("Wall Calendar"), _("Calendars"), _("Twelve landscape A4 months with a picture and a date grid")));
            l.add (new TemplateInfo ("envelope", _("Envelope"), _("Stationery"), _("DL envelope with a return address and a recipient block")));
            l.add (new TemplateInfo ("labels", _("Address Labels"), _("Stationery"), _("70 by 37 mm labels, printed twenty-four to an A4 sheet")));
            l.add (new TemplateInfo ("invoice", _("Invoice"), _("Business Forms"), _("A4 invoice with an item table and totals")));
            l.add (new TemplateInfo ("gift-certificate", _("Gift Certificate"), _("Cards"), _("Long gift voucher with a tear-off stub")));
            l.add (new TemplateInfo ("sign", _("Sign"), _("Signs and Banners"), _("Landscape A4 notice for a door or a window")));
            l.add (new TemplateInfo ("banner", _("Banner"), _("Signs and Banners"), _("Six by two foot banner, printed in tiles or by a print shop")));
            return l;
        }

        public static TemplateInfo? find (string id) {
            foreach (var t in all ()) if (t.id == id) return t;
            return null;
        }

        public static Publication blank (DocSettings s, int pages) {
            var p = Publication.create (s, int.max (1, pages));
            add_page_number_master (p);
            return p;
        }

        public static Publication build (string id) {
            switch (id) {
                case "flyer": return flyer ();
                case "brochure": return brochure ();
                case "newsletter": return newsletter ();
                case "business-cards": return business_cards ();
                case "poster": return poster ();
                case "greeting-card": return greeting_card ();
                case "menu": return menu ();
                case "certificate": return certificate ();
                case "invitation": return invitation ();
                case "postcard": return postcard ();
                case "letterhead": return letterhead ();
                case "resume": return resume ();
                case "program": return program ();
                case "calendar": return calendar ();
                case "envelope": return envelope ();
                case "labels": return labels ();
                case "invoice": return invoice ();
                case "gift-certificate": return gift_certificate ();
                case "sign": return sign ();
                case "banner": return banner ();
                default: return blank (new DocSettings (), 1);
            }
        }

        private static double mm (double v) {
            return v * Units.PT_PER_MM;
        }

        private static DocSettings settings (double w, double h, double margin, double bleed, string size_id) {
            var s = new DocSettings ();
            s.width = w;
            s.height = h;
            s.set_margins (margin);
            s.set_bleed (bleed);
            s.page_size = size_id;
            s.baseline_start = margin;
            return s;
        }

        private static string swatch (Publication p, string name, double c, double m, double y, double k) {
            if (p.swatch (name) == null) p.swatches.add (new Swatch.cmyk (name, c, m, y, k));
            return ColorRef.swatch (name);
        }

        private static ParagraphStyle pstyle (Publication p, string name, string based, string? font, double size, double leading, int align = -1, int bold = -1, string? color = null) {
            var s = p.styles.find_paragraph (name);
            if (s == null) {
                s = new ParagraphStyle (name, based);
                p.styles.paragraph.add (s);
            }
            s.based_on = based;
            if (font != null) s.chars.font = font;
            if (size > 0) s.chars.size = size;
            if (leading > 0) s.para.leading = leading;
            if (align >= 0) s.para.align = align;
            if (bold >= 0) s.chars.bold = bold;
            if (color != null) s.chars.color = color;
            return s;
        }

        private static Paragraph paragraph (string spec) {
            string style = StyleSheet.BASIC;
            string text = spec;
            int bar = spec.index_of ("|");
            if (bar >= 0) {
                style = spec.substring (0, bar);
                text = spec.substring (bar + 1);
            }
            var p = new Paragraph (style);
            var sb = new StringBuilder ();
            bool strong = false;
            int i = 0;
            while (i < text.length) {
                if (text.substring (i).has_prefix ("{page}")) {
                    flush (p, sb, strong);
                    p.runs.add (new Run.field_run (Fields.PAGE));
                    i += 6;
                    continue;
                }
                if (text.substring (i).has_prefix ("**")) {
                    flush (p, sb, strong);
                    strong = !strong;
                    i += 2;
                    continue;
                }
                sb.append_c (text[i]);
                i++;
            }
            flush (p, sb, strong);
            if (p.runs.size == 0) p.runs.add (new Run (""));
            return p;
        }

        private static void flush (Paragraph p, StringBuilder sb, bool strong) {
            if (sb.len == 0) return;
            var r = new Run (sb.str);
            if (strong) r.cstyle = "Strong";
            p.runs.add (r);
            sb.truncate ();
        }

        private static TextFrame text (Publication p, Gee.ArrayList<Item> list, double x, double y, double w, double h, string[] paras) {
            var t = p.add_text_frame (list, x, y, w, h);
            var s = p.stories[t.story];
            s.paras.clear ();
            foreach (string sp in paras) s.paras.add (paragraph (sp));
            if (s.paras.size == 0) s.paras.add (new Paragraph.with_text (""));
            return t;
        }

        private static TextFrame thread (Publication p, Gee.ArrayList<Item> list, TextFrame prev, double x, double y, double w, double h) {
            var t = new TextFrame ();
            t.id = p.next_id ();
            t.x = x;
            t.y = y;
            t.w = w;
            t.h = h;
            t.layer = p.default_layer ().id;
            t.story = prev.story;
            t.columns = prev.columns;
            t.gutter = prev.gutter;
            var s = p.stories[prev.story];
            s.frames.insert (s.frames.index_of (prev.id) + 1, t.id);
            list.add (t);
            return t;
        }

        private static ShapeItem shape (Publication p, Gee.ArrayList<Item> list, ShapeKind kind, double x, double y, double w, double h, string fill) {
            var s = new ShapeItem (kind);
            s.id = p.next_id ();
            s.x = x;
            s.y = y;
            s.w = w;
            s.h = h;
            s.layer = p.default_layer ().id;
            if (fill != ColorRef.NONE) s.fill = new Fill.solid (fill);
            list.add (s);
            return s;
        }

        private static ShapeItem rect (Publication p, Gee.ArrayList<Item> list, double x, double y, double w, double h, string fill) {
            return shape (p, list, ShapeKind.RECT, x, y, w, h, fill);
        }

        private static ShapeItem ellipse (Publication p, Gee.ArrayList<Item> list, double x, double y, double w, double h, string fill) {
            return shape (p, list, ShapeKind.ELLIPSE, x, y, w, h, fill);
        }

        private static ShapeItem hline (Publication p, Gee.ArrayList<Item> list, double x, double y, double w, string color, double width) {
            var s = shape (p, list, ShapeKind.LINE, x, y, w, 0, ColorRef.NONE);
            s.stroke = new Stroke.with (color, width);
            return s;
        }

        private static ShapeItem vline (Publication p, Gee.ArrayList<Item> list, double x, double y, double h, string color, double width) {
            var s = shape (p, list, ShapeKind.LINE, x, y, 0, h, ColorRef.NONE);
            s.stroke = new Stroke.with (color, width);
            return s;
        }

        private static ImageFrame picture (Publication p, Gee.ArrayList<Item> list, double x, double y, double w, double h, string a, string b) {
            var im = new ImageFrame ();
            im.id = p.next_id ();
            im.x = x;
            im.y = y;
            im.w = w;
            im.h = h;
            im.layer = p.default_layer ().id;
            im.fill = new Fill.linear (a, b, 60);
            list.add (im);
            return im;
        }

        private static void add_page_number_master (Publication p) {
            var m = p.masters[0];
            var s = p.settings;
            double y = s.height - s.margin_bottom + 8;
            var right = text (p, m.items, s.width - s.margin_outside - 60, y, 60, 14, { "Folio|{page}" });
            right.valign = 0;
            pstyle (p, "Folio", StyleSheet.BASIC, SANS, 8, 10, (int) TextAlign.RIGHT);
            if (s.facing) text (p, m.left_items, s.margin_outside, y, 60, 14, { "Folio Left|{page}" });
            pstyle (p, "Folio Left", "Folio", null, 0, 0, (int) TextAlign.LEFT);
        }

        private static Gee.ArrayList<TabStop> tabs (double pos, TabKind kind, string leader) {
            var l = new Gee.ArrayList<TabStop> ();
            l.add (new TabStop (pos, kind, leader));
            return l;
        }

        private static Publication flyer () {
            double w = 595.28, h = 841.89;
            var s = settings (w, h, mm (15), mm (3), "a4");
            s.columns = 2;
            s.gutter = mm (6);
            var p = Publication.create (s, 1);
            p.meta.title = _("Summer Jazz Nights");
            string navy = swatch (p, "Midnight", 0.95, 0.85, 0.30, 0.35);
            string coral = swatch (p, "Coral", 0.00, 0.70, 0.65, 0.00);
            string sun = swatch (p, "Sunflower", 0.00, 0.25, 0.90, 0.00);
            string mist = swatch (p, "Mist", 0.06, 0.02, 0.00, 0.02);
            string ink = swatch (p, "Ink", 0.70, 0.60, 0.45, 0.60);
            pstyle (p, "Display", StyleSheet.BASIC, SANS, 54, 56, (int) TextAlign.LEFT, 1, ColorRef.PAPER).chars.tracking = -20;
            pstyle (p, "Kicker", StyleSheet.BASIC, SANS, 11, 14, (int) TextAlign.LEFT, 1, sun).chars.tracking = 200;
            p.styles.find_paragraph ("Kicker").chars.caps = 1;
            pstyle (p, "Lead", StyleSheet.BASIC, SANS, 15, 21, (int) TextAlign.LEFT, 0, ColorRef.PAPER);
            pstyle (p, "Flyer Body", "Body Text", SANS, 10.5, 15, (int) TextAlign.LEFT, 0, ink);
            pstyle (p, "Flyer Heading", "Heading 2", SANS, 16, 20, -1, 1, navy).para.space_after = 6;
            pstyle (p, "Info Label", StyleSheet.BASIC, SANS, 8, 11, -1, 1, coral).chars.caps = 1;
            p.styles.find_paragraph ("Info Label").chars.tracking = 120;
            pstyle (p, "Info Text", StyleSheet.BASIC, SANS, 13, 17, -1, 1, navy).para.space_after = 10;
            pstyle (p, "Footer", StyleSheet.BASIC, SANS, 10, 13, (int) TextAlign.CENTER, 0, ColorRef.PAPER);
            var items = p.pages[0].items;
            double b = mm (3);
            var hero = rect (p, items, -b, -b, w + 2 * b, 430 + b, navy);
            hero.fill = new Fill.linear (navy, swatch (p, "Plum", 0.60, 0.95, 0.20, 0.10), 45);
            var c1 = ellipse (p, items, 318, -8, 285, 285, coral);
            c1.opacity = 0.85;
            var c2 = ellipse (p, items, 455, 185, 140, 140, sun);
            c2.opacity = 0.9;
            var c3 = ellipse (p, items, 300, 250, 70, 70, ColorRef.PAPER);
            c3.opacity = 0.25;
            text (p, items, mm (15), 150, 340, 30, { "Kicker|Riverside Park Amphitheatre" });
            text (p, items, mm (15), 180, 380, 125, { "Display|Summer Jazz Nights" });
            text (p, items, mm (15), 318, 330, 80, { "Lead|Four evenings of live music under the stars, with local food, craft drinks and open lawn seating." });
            text (p, items, mm (15), 660, 300, 56, {
                "Info Label|Line-up",
                "Flyer Body|Marlow Quartet, Ines Duarte, Northside Big Band and the closing night jam session"
            });
            var body = text (p, items, mm (15), 470, 300, 180, {
                "Flyer Heading|Bring a blanket, stay for the encore",
                "Flyer Body|Every Friday in July the amphitheatre opens its gates at six. The first set begins at seven, and the headliners take the stage as the sun goes down over the river.",
                "Flyer Body|This year features the Marlow Quartet, vocalist Ines Duarte, the Northside Big Band and a closing night jam session open to every musician who brings an instrument.",
                "Flyer Body|Children under twelve enter free. Seating is first come, first served, and the park is fully accessible."
            });
            body.columns = 1;
            var card = rect (p, items, 372, 470, 180, 250, mist);
            card.corner = CornerKind.ROUNDED;
            card.corner_radius = 10;
            var info = text (p, items, 388, 486, 150, 222, {
                "Info Label|When",
                "Info Text|Fridays in July, 6 pm",
                "Info Label|Where",
                "Info Text|Riverside Park, 40 Quay Road",
                "Info Label|Tickets",
                "Info Text|From 15, season pass 48"
            });
            info.valign = 0;
            var foot = rect (p, items, -b, h - 70, w + 2 * b, 70 + b, coral);
            foot.fill = new Fill.linear (coral, swatch (p, "Tangerine", 0.00, 0.55, 0.85, 0.00), 0);
            var ft = text (p, items, mm (15), h - 52, w - mm (30), 34, { "Footer|**riversidejazz.example**   Book online or call 555 0142" });
            ft.valign = 1;
            return p;
        }

        private static Publication brochure () {
            double w = 841.89, h = 595.28;
            var s = settings (w, h, mm (10), mm (3), "a4");
            s.columns = 3;
            s.gutter = mm (20);
            var p = Publication.create (s, 2);
            p.meta.title = _("Greenway Architects");
            double panel = w / 3;
            foreach (var pg in p.pages) {
                pg.guides.add (new Guide (true, panel));
                pg.guides.add (new Guide (true, panel * 2));
            }
            string forest = swatch (p, "Forest", 0.80, 0.30, 0.75, 0.30);
            string sage = swatch (p, "Sage", 0.25, 0.05, 0.30, 0.00);
            string sand = swatch (p, "Sand", 0.03, 0.05, 0.12, 0.00);
            string charcoal = swatch (p, "Charcoal", 0.60, 0.50, 0.45, 0.70);
            pstyle (p, "Panel Heading", "Heading 2", SANS, 17, 21, -1, 1, forest).para.space_after = 6;
            pstyle (p, "Panel Body", "Body Text", SANS, 9.5, 14, (int) TextAlign.LEFT, 0, charcoal).para.space_after = 6;
            pstyle (p, "Cover Title", StyleSheet.BASIC, SANS, 34, 36, -1, 1, ColorRef.PAPER);
            pstyle (p, "Cover Sub", StyleSheet.BASIC, SANS, 12, 17, -1, 0, ColorRef.PAPER);
            pstyle (p, "Contact", StyleSheet.BASIC, SANS, 10, 15, (int) TextAlign.CENTER, 0, charcoal);
            pstyle (p, "Brochure Bullet", "Bulleted List", SANS, 9.5, 14, -1, 0, charcoal);
            double m = mm (10), b = mm (3), cw = panel - 2 * m;
            var out_items = p.pages[0].items;
            rect (p, out_items, -b, -b, panel + b, h + 2 * b, sand);
            text (p, out_items, m, m + 10, cw, 180, {
                "Panel Heading|Designed around the way you live",
                "Panel Body|Greenway has spent twenty years turning tight city lots and forgotten barns into light-filled homes. We listen first, draw second and stay with you until the last shelf is in place.",
                "Panel Body|Every project starts with a free site visit and an honest estimate."
            });
            var pic = picture (p, out_items, m, 260, cw, 150, sage, forest);
            pic.corner = CornerKind.ROUNDED;
            pic.corner_radius = 6;
            text (p, out_items, m, 425, cw, 120, {
                "Brochure Bullet|Residential new builds",
                "Brochure Bullet|Heritage restoration",
                "Brochure Bullet|Energy retrofits",
                "Brochure Bullet|Interior planning"
            });
            var logo = ellipse (p, out_items, panel + panel / 2 - 34, 150, 68, 68, forest);
            logo.stroke = new Stroke.with (sage, 3);
            var contact = text (p, out_items, panel + m, 245, cw, 200, {
                "Panel Heading|Visit the studio",
                "Contact|12 Mill Lane, Harrowgate",
                "Contact|Monday to Friday, 9 to 5",
                "Contact|studio@greenway.example",
                "Contact|555 0188"
            });
            p.styles.find_paragraph ("Panel Heading").para.align = -1;
            var cover = rect (p, out_items, panel * 2, -b, panel + b, h + 2 * b, forest);
            cover.fill = new Fill.linear (forest, swatch (p, "Pine", 0.90, 0.45, 0.80, 0.55), 90);
            var roof = shape (p, out_items, ShapeKind.POLYGON, panel * 2 + 60, 110, 160, 140, sage);
            roof.sides = 3;
            roof.opacity = 0.9;
            var door = rect (p, out_items, panel * 2 + 125, 200, 30, 50, sand);
            door.corner = CornerKind.ROUNDED;
            door.corner_radius = 4;
            text (p, out_items, panel * 2 + m, 330, cw, 90, { "Cover Title|Greenway Architects" });
            text (p, out_items, panel * 2 + m, 430, cw, 60, { "Cover Sub|Homes that fit the land and the people in them." });
            contact.valign = 0;
            var in_items = p.pages[1].items;
            string[] heads = { "Listen", "Design", "Build" };
            string[] bodies = {
                "We start at your kitchen table. How you cook, work, rest and host friends shapes every room we draw, so the first meeting is mostly questions.",
                "Sketches become models, and models become drawings you can walk through on screen. Nothing is fixed until it feels right to you.",
                "Our site architects visit every week, keep the budget in view and hand over a home with a full maintenance guide."
            };
            string[] tints = { "Sage", "Forest", "Sand" };
            for (int i = 0; i < 3; i++) {
                double x = i * panel + m;
                var im = picture (p, in_items, x, m + 8, cw, 170, ColorRef.swatch (tints[i]), ColorRef.swatch (tints[(i + 1) % 3]));
                im.corner = CornerKind.ROUNDED;
                im.corner_radius = 6;
                text (p, in_items, x, 225, cw, 280, {
                    "Panel Heading|%d. %s".printf (i + 1, heads[i]),
                    "Panel Body|" + bodies[i],
                    "Panel Body|Clients describe this stage as the one where the house starts to feel like theirs, long before the first stone is laid."
                });
            }
            hline (p, in_items, m, h - 60, w - 2 * m, sage, 1);
            var tag = text (p, in_items, m, h - 50, w - 2 * m, 24, { "Contact|Free site visits across the county. Ask for our project book." });
            tag.valign = 1;
            return p;
        }

        private static Publication newsletter () {
            double w = 595.28, h = 841.89;
            var s = settings (w, h, mm (18), 0, "a4");
            s.facing = true;
            s.margin_top = mm (22);
            s.margin_bottom = mm (20);
            s.margin_inside = mm (20);
            s.margin_outside = mm (15);
            s.columns = 3;
            s.gutter = mm (5);
            s.baseline_start = s.margin_top;
            s.baseline_step = 13.5;
            var p = Publication.create (s, 4);
            p.meta.title = _("The Harbour Gazette");
            string teal = swatch (p, "Harbour Teal", 0.85, 0.20, 0.35, 0.10);
            string rust = swatch (p, "Rust", 0.10, 0.75, 0.90, 0.10);
            string fog = swatch (p, "Fog", 0.08, 0.03, 0.03, 0.00);
            string ink = swatch (p, "Ink", 0.70, 0.60, 0.45, 0.70);
            pstyle (p, "Masthead", StyleSheet.BASIC, SERIF, 38, 44, (int) TextAlign.LEFT, 1, teal);
            pstyle (p, "Dateline", StyleSheet.BASIC, SANS, 9, 12, -1, 0, ink).chars.caps = 1;
            p.styles.find_paragraph ("Dateline").chars.tracking = 100;
            pstyle (p, "Headline", StyleSheet.BASIC, SERIF, 26, 29, -1, 1, ink).para.space_after = 8;
            pstyle (p, "Standfirst", StyleSheet.BASIC, SANS, 11.5, 16, -1, 0, teal).para.space_after = 10;
            var nb = pstyle (p, "News Body", "Body Text", SERIF, 9.5, 13.5, (int) TextAlign.LEFT, 0, ink);
            nb.para.first_indent = 10;
            nb.para.space_after = 0;
            nb.para.align_grid = 1;
            nb.para.hyphenate = 1;
            var lead = pstyle (p, "News Lead", "News Body", null, 0, 0);
            lead.para.first_indent = 0;
            lead.para.drop_lines = 3;
            lead.para.drop_chars = 1;
            lead.chars.color = ink;
            var sub = pstyle (p, "News Subhead", "News Body", SANS, 10.5, 13.5, (int) TextAlign.LEFT, 1, rust);
            sub.para.first_indent = 0;
            sub.para.space_before = 6;
            sub.para.keep_next = 1;
            var pq = pstyle (p, "Pull Quote", StyleSheet.BASIC, SERIF, 15, 20, (int) TextAlign.CENTER, 0, teal);
            pq.chars.italic = 1;
            pq.para.rule_above = "1;" + rust + ";6";
            pq.para.rule_below = "1;" + rust + ";6";
            pstyle (p, "Running Head", StyleSheet.BASIC, SANS, 8, 10, -1, 1, teal).chars.caps = 1;
            pstyle (p, "Folio", StyleSheet.BASIC, SANS, 8, 10, (int) TextAlign.RIGHT, 0, ink);
            pstyle (p, "Folio Left", "Folio", null, 0, 0, (int) TextAlign.LEFT);
            pstyle (p, "Box Heading", StyleSheet.BASIC, SANS, 11, 14, -1, 1, ColorRef.PAPER).chars.caps = 1;
            pstyle (p, "Box Item", StyleSheet.BASIC, SANS, 9.5, 14, -1, 0, ColorRef.PAPER);
            pstyle (p, "Event", StyleSheet.BASIC, SANS, 9.5, 17, -1, 0, ink).para.tabs = TabStop.serialize (tabs (160, TabKind.RIGHT, "."));
            pstyle (p, "Caption Text", "Caption", SANS, 8, 10.5, -1, 0, ink);
            var m = p.masters[0];
            double top = s.margin_top;
            double inner_r = s.margin_inside, outer = s.margin_outside;
            hline (p, m.items, inner_r, top - 12, w - inner_r - outer, teal, 1.5);
            text (p, m.items, inner_r, top - 28, 250, 14, { "Running Head|The Harbour Gazette" });
            text (p, m.items, w - outer - 80, h - s.margin_bottom + 12, 80, 14, { "Folio|Page {page}" });
            hline (p, m.left_items, outer, top - 12, w - inner_r - outer, teal, 1.5);
            text (p, m.left_items, w - inner_r - 250, top - 28, 250, 14, { "Running Head|Autumn Issue" });
            p.styles.find_paragraph ("Running Head").para.align = -1;
            text (p, m.left_items, outer, h - s.margin_bottom + 12, 80, 14, { "Folio Left|Page {page}" });
            var p1 = p.pages[0];
            p1.hide_master = true;
            var mr = p.margin_rect (0);
            var mast_bar = rect (p, p1.items, mr.x, mr.y - 20, mr.w, 4, teal);
            mast_bar.name = _("Masthead Rule");
            text (p, p1.items, mr.x, mr.y - 8, mr.w, 54, { "Masthead|The Harbour Gazette" });
            text (p, p1.items, mr.x, mr.y + 48, mr.w, 16, { "Dateline|Autumn issue   Community news from Porthaven   Free" });
            hline (p, p1.items, mr.x, mr.y + 68, mr.w, ink, 0.5);
            text (p, p1.items, mr.x, mr.y + 80, mr.w, 110, {
                "Headline|The old ferry pier opens again after two years of repairs",
                "Standfirst|Volunteers, divers and a very patient crane driver brought the landmark back in time for the winter timetable."
            });
            double colw = (mr.w - 2 * s.gutter) / 3;
            var img = picture (p, p1.items, mr.x + colw + s.gutter, mr.y + 200, 2 * colw + s.gutter, 190, fog, teal);
            img.wrap = WrapMode.BOUNDING_BOX;
            img.wrap_offset = 8;
            text (p, p1.items, mr.x + colw + s.gutter, mr.y + 394, 2 * colw + s.gutter, 20, { "Caption Text|The restored pier at low tide, photographed from the harbour wall." }).wrap = WrapMode.BOUNDING_BOX;
            var art = p.add_text_frame (p1.items, mr.x, mr.y + 200, mr.w, mr.h - 200 - 110);
            art.columns = 3;
            art.gutter = s.gutter;
            var story = p.stories[art.story];
            story.paras.clear ();
            string[] body = {
                "News Lead|When the last timber pile of the old ferry pier was lifted from the mud in the spring of last year, few people in Porthaven expected to walk its length again before retirement. Yet on a grey Saturday morning in September, more than four hundred residents lined up behind the brass band to do exactly that.",
                "News Body|The repair was always going to be difficult. Salt had eaten through the iron straps that held the deck together, and the original drawings from 1889 had been lost in a flood at the town hall. Engineers had to rebuild the plans by measuring every beam that remained.",
                "News Body|Divers from the sailing club spent three winters mapping the footings. Their survey showed that the stone base was sound, which saved the council from the far more expensive option of starting again from nothing.",
                "News Subhead|A town effort",
                "News Body|Money came from everywhere. The school ran a sponsored swim, the bakery sold a pier-shaped loaf for a whole summer, and an anonymous donor paid for the new lamps along the rail. In total the appeal raised a little over a third of the final cost.",
                "News Body|The rest came from a regional heritage grant, awarded after the parish council showed that the pier would once again carry the ferry that links the town with the island villages across the bay.",
                "News Body|Harbour master Tom Penrose said the crew had worked through two storms and one memorable week when a seal refused to leave the scaffolding. The seal, now known locally as Gerald, was given a plaque of his own.",
                "News Subhead|What happens next",
                "News Body|The ferry resumes its winter timetable on the first of November, with four crossings a day and an extra evening boat on market days. Fares stay the same as before the closure.",
                "News Body|A small exhibition about the rebuild opens in the library next month, with photographs, the divers' survey maps and a scale model made by pupils of the primary school.",
                "News Body|The council has also asked for volunteers to join a friends of the pier group, which will look after the paintwork, the benches and the flower boxes along the approach.",
                "News Body|Anyone interested can sign up at the harbour office or at the next community meeting, which takes place on the second Tuesday of the month in the church hall.",
                "News Subhead|Looking back",
                "News Body|The pier was first built to land slate from the quarries up the valley. By the turn of the century it carried more holidaymakers than cargo, and the steamers from the city called three times a day in summer.",
                "News Body|Older residents still remember the tea room at the end of the deck, the penny telescope and the diving boards that were taken down after the war. Several of them lent photographs to the library exhibition.",
                "News Body|The engineers kept one of the original iron straps, green with age, which now hangs in the harbour office beside a framed copy of the 1889 opening poster."
            };
            foreach (string sp in body) story.paras.add (paragraph (sp));
            var box = rect (p, p1.items, mr.x, mr.y + mr.h - 96, mr.w, 96, teal);
            box.corner = CornerKind.ROUNDED;
            box.corner_radius = 6;
            var inside = text (p, p1.items, mr.x + 14, mr.y + mr.h - 86, mr.w - 28, 78, {
                "Box Heading|In this issue",
                "Box Item|Pier reopens, page 1     Market days return, page 2     Harvest supper, page 3     What's on, page 4"
            });
            inside.columns = 1;
            var p2 = p.pages[1];
            var r2 = p.margin_rect (1);
            thread (p, p2.items, art, r2.x, r2.y, r2.w, r2.h * 0.5);
            var quote = text (p, p2.items, r2.x + colw + s.gutter, r2.y + 110, colw * 2 + s.gutter, 90, { "Pull Quote|The seal refused to leave the scaffolding, so we gave him a plaque of his own." });
            quote.wrap = WrapMode.BOUNDING_BOX;
            quote.wrap_offset = 10;
            quote.valign = 1;
            text (p, p2.items, r2.x, r2.y + r2.h * 0.5 + 16, r2.w, 60, {
                "Headline|Market days return to the square",
                "Standfirst|Fourteen stalls, two new bakers and a coffee cart every Thursday."
            });
            var art2 = text (p, p2.items, r2.x, r2.y + r2.h * 0.5 + 84, r2.w, r2.h * 0.5 - 84, {
                "News Lead|After a quiet summer the Thursday market is back in the square, with fourteen stalls confirmed for the autumn and a waiting list for the Christmas fair. Organisers moved the pitches closer to the fountain so the ramp from the car park stays clear.",
                "News Body|Regulars will find the fishmonger, the cheese van and the flower stall in their usual places. New this year are two bakers from the valley and a coffee cart run by students from the college.",
                "News Body|The market opens at eight and packs away at two. Parking in the harbour car park is free before ten for shoppers with a market token.",
                "News Subhead|New faces",
                "News Body|Rosa and Dev Mehta bake sourdough and cardamom buns in a converted dairy above the valley road. They sold out by eleven on their first morning and have promised a second batch for the busier weeks before Christmas.",
                "News Body|The coffee cart is run by hospitality students as part of their course. Every cup is served in a returnable mug, and the deposit goes to the school's travel fund.",
                "News Body|Stallholders are still looking for a greengrocer and a knife sharpener. Anyone interested can ask for a pitch at the harbour office, where the first month is offered free to new traders."
            });
            art2.columns = 3;
            art2.gutter = s.gutter;
            var p3 = p.pages[2];
            var r3 = p.margin_rect (2);
            var sup = picture (p, p3.items, r3.x, r3.y, r3.w, 280, rust, fog);
            sup.corner = CornerKind.ROUNDED;
            sup.corner_radius = 6;
            text (p, p3.items, r3.x, r3.y + 296, r3.w, 60, {
                "Headline|Harvest supper",
                "Standfirst|Long tables, local produce and a band in the boathouse."
            });
            var art3 = text (p, p3.items, r3.x, r3.y + 364, r3.w, 190, {
                "News Lead|The rowing club opens its boathouse for the harvest supper on the last Saturday of October. Tickets include three courses cooked with produce from the allotments and a glass of cider from the orchard on the hill.",
                "News Body|Tables seat ten, so bring friends or make some. The band starts at nine and plays until the last dance, with a break at eleven for the raffle and the traditional toast to the fishing fleet.",
                "News Body|Tickets are on sale at the post office and the bakery. Last year the supper sold out in a week, so the club has added two more tables along the slipway, under a marquee lit with festoon lamps.",
                "News Subhead|Cooking together",
                "News Body|Volunteers meet in the club kitchen from two o'clock to peel, chop and gossip. No experience is needed, only an apron and a sharp knife, and helpers eat for free.",
                "News Body|Any money left over after costs goes towards a new rescue launch for the club's youth squad, who train on the estuary every Sunday morning from April to October."
            });
            art3.columns = 3;
            art3.gutter = s.gutter;
            var lb = rect (p, p3.items, r3.x, r3.y + r3.h - 130, r3.w, 130, fog);
            lb.corner = CornerKind.ROUNDED;
            lb.corner_radius = 6;
            var lt = text (p, p3.items, r3.x + 16, r3.y + r3.h - 118, r3.w - 32, 106, {
                "News Subhead|Lantern walk photo competition",
                "News Body|Send your best picture of the lantern walk to the harbour office by the end of November. The winner will appear on the cover of the winter Gazette and receive a family ticket for the ferry."
            });
            lt.valign = 1;
            var p4 = p.pages[3];
            var r4 = p.margin_rect (3);
            text (p, p4.items, r4.x, r4.y, r4.w, 40, { "Headline|What's on" });
            var ev = text (p, p4.items, r4.x, r4.y + 50, 170, 370, {
                "Event|Library exhibition\tNov 2",
                "Event|Ferry winter timetable\tNov 1",
                "Event|Community meeting\tNov 11",
                "Event|Lantern walk\tNov 18",
                "Event|Harvest supper\tOct 28",
                "Event|Christmas fair\tDec 9",
                "Event|Carols on the pier\tDec 20"
            });
            ev.fill = new Fill.solid (fog);
            ev.inset_left = ev.inset_right = ev.inset_top = ev.inset_bottom = 8;
            p.styles.find_paragraph ("Event").para.tabs = TabStop.serialize (tabs (154, TabKind.RIGHT, "."));
            var pic4 = picture (p, p4.items, r4.x + 186, r4.y + 50, r4.w - 186, 370, teal, fog);
            pic4.corner = CornerKind.ROUNDED;
            pic4.corner_radius = 6;
            var contact = text (p, p4.items, r4.x, r4.y + 444, r4.w, 130, {
                "News Subhead|Write for the Gazette",
                "News Body|The Gazette is written by volunteers and delivered free to every home in Porthaven. Send letters, photographs and news to the harbour office or leave them in the box at the library. The deadline for the winter issue is the first of December.",
                "News Subhead|Advertise with us",
                "News Body|Local businesses can book a quarter page for the price of a coffee a week. Ask at the harbour office."
            });
            contact.columns = 2;
            contact.gutter = s.gutter;
            var next = rect (p, p4.items, r4.x, r4.y + r4.h - 120, r4.w, 120, teal);
            next.corner = CornerKind.ROUNDED;
            next.corner_radius = 6;
            var nt = text (p, p4.items, r4.x + 16, r4.y + r4.h - 106, r4.w - 32, 92, {
                "Box Heading|Next issue",
                "Box Item|The winter Gazette arrives on the fifteenth of December, with the carol programme, the ferry timetable for the holidays and the results of the lantern walk photo competition."
            });
            nt.valign = 1;
            return p;
        }

        private static Publication business_cards () {
            double w = mm (85), h = mm (55);
            var s = settings (w, h, mm (5), mm (3), "card-eu");
            s.impose = "nup:2x5:a4";
            s.units = "mm";
            var p = Publication.create (s, 2);
            p.meta.title = _("Business Cards");
            string indigo = swatch (p, "Indigo", 0.90, 0.80, 0.10, 0.10);
            string sky = swatch (p, "Sky", 0.70, 0.25, 0.00, 0.00);
            string slate = swatch (p, "Slate", 0.55, 0.40, 0.30, 0.45);
            pstyle (p, "Card Name", StyleSheet.BASIC, SANS, 13, 15, -1, 1, indigo);
            pstyle (p, "Card Role", StyleSheet.BASIC, SANS, 7.5, 10, -1, 0, sky).chars.caps = 1;
            p.styles.find_paragraph ("Card Role").chars.tracking = 100;
            pstyle (p, "Card Detail", StyleSheet.BASIC, SANS, 7, 10, -1, 0, slate);
            pstyle (p, "Card Brand", StyleSheet.BASIC, SANS, 14, 17, (int) TextAlign.CENTER, 1, ColorRef.PAPER).chars.tracking = 60;
            pstyle (p, "Card Tag", StyleSheet.BASIC, SANS, 6.5, 9, (int) TextAlign.CENTER, 0, ColorRef.PAPER);
            double b = mm (3), m = mm (5);
            var front = p.pages[0].items;
            var bar = rect (p, front, -b, -b, mm (6) + b, h + 2 * b, indigo);
            bar.fill = new Fill.linear (sky, indigo, 90);
            text (p, front, mm (11), m + 2, w - mm (16), 36, {
                "Card Name|Mara Lindqvist",
                "Card Role|Lead Product Designer"
            });
            hline (p, front, mm (11), 64, 40, sky, 1.5);
            var mark = shape (p, front, ShapeKind.STAR, w - m - 16, m + 2, 16, 16, indigo);
            mark.sides = 5;
            mark.star_inset = 0.45;
            text (p, front, mm (11), 76, w - mm (16), h - 76 - m + 2, {
                "Card Detail|mara@northlight.example",
                "Card Detail|+46 555 014 22",
                "Card Detail|Studio 4, Kvarngatan 9, Uppsala"
            });
            var back = p.pages[1].items;
            var bg = rect (p, back, -b, -b, w + 2 * b, h + 2 * b, indigo);
            bg.fill = new Fill.linear (indigo, swatch (p, "Deep Indigo", 1.0, 0.90, 0.20, 0.40), 120);
            var star = shape (p, back, ShapeKind.STAR, w / 2 - 14, 24, 28, 28, sky);
            star.sides = 5;
            star.star_inset = 0.45;
            text (p, back, m, 60, w - 2 * m, 20, { "Card Brand|NORTHLIGHT" });
            text (p, back, m, 82, w - 2 * m, 14, { "Card Tag|Interfaces for long winters" });
            return p;
        }

        private static Publication poster () {
            double w = mm (420), h = mm (594);
            var s = settings (w, h, mm (25), mm (3), "a2");
            var p = Publication.create (s, 1);
            p.meta.title = _("Light and Glass");
            string night = swatch (p, "Night", 0.85, 0.75, 0.35, 0.55);
            string magenta = swatch (p, "Fuchsia", 0.10, 0.90, 0.00, 0.00);
            string amber = swatch (p, "Amber", 0.00, 0.40, 0.95, 0.00);
            string ice = swatch (p, "Ice", 0.35, 0.00, 0.05, 0.00);
            pstyle (p, "Poster Kicker", StyleSheet.BASIC, SANS, 28, 34, -1, 1, amber).chars.tracking = 250;
            p.styles.find_paragraph ("Poster Kicker").chars.caps = 1;
            pstyle (p, "Poster Title", StyleSheet.BASIC, SANS, 150, 140, -1, 1, ColorRef.PAPER).chars.tracking = -30;
            pstyle (p, "Poster Sub", StyleSheet.BASIC, SANS, 34, 44, -1, 0, ice);
            pstyle (p, "Poster Info", StyleSheet.BASIC, SANS, 26, 34, -1, 1, ColorRef.PAPER);
            pstyle (p, "Poster Small", StyleSheet.BASIC, SANS, 20, 28, -1, 0, ice);
            var items = p.pages[0].items;
            double b = mm (3), m = mm (25);
            var bg = rect (p, items, -b, -b, w + 2 * b, h + 2 * b, night);
            bg.fill = new Fill.linear (night, swatch (p, "Violet Night", 0.75, 0.90, 0.20, 0.35), 110);
            var big = ellipse (p, items, w * 0.3, h * 0.04, w * 0.7 + 8, w * 0.7 + 8, magenta);
            big.opacity = 0.75;
            var mid = ellipse (p, items, w * 0.55, h * 0.3, w * 0.35, w * 0.35, amber);
            mid.opacity = 0.85;
            var ring = ellipse (p, items, w * 0.1, h * 0.05, w * 0.3, w * 0.3, ColorRef.NONE);
            ring.stroke = new Stroke.with (ice, 6);
            var st = shape (p, items, ShapeKind.STAR, w * 0.12, h * 0.36, 120, 120, ice);
            st.sides = 4;
            st.star_inset = 0.25;
            var poly = shape (p, items, ShapeKind.POLYGON, w * 0.7, h * 0.02, 140, 140, ColorRef.NONE);
            poly.sides = 6;
            poly.stroke = new Stroke.with (amber, 4);
            text (p, items, m, h * 0.5, w - 2 * m, 40, { "Poster Kicker|City Gallery presents" });
            text (p, items, m, h * 0.5 + 50, w - 2 * m, 340, { "Poster Title|Light and Glass" });
            text (p, items, m, h * 0.5 + 400, w * 0.7, 100, { "Poster Sub|Forty years of stained glass, neon and projected light from artists across the north." });
            hline (p, items, m, h - m - 150, w - 2 * m, ice, 2);
            var info = text (p, items, m, h - m - 130, (w - 2 * m) / 2, 130, {
                "Poster Info|14 March to 30 June",
                "Poster Small|Tuesday to Sunday, 10 am to 6 pm"
            });
            info.valign = 0;
            text (p, items, m + (w - 2 * m) / 2, h - m - 130, (w - 2 * m) / 2, 130, {
                "Poster Info|City Gallery, Harbour Street",
                "Poster Small|Free entry. gallery.example"
            });
            return p;
        }

        private static Publication greeting_card () {
            double w = mm (210), h = mm (148);
            var s = settings (w, h, mm (8), mm (3), "a5");
            var p = Publication.create (s, 2);
            p.meta.title = _("Greeting Card");
            foreach (var pg in p.pages) pg.guides.add (new Guide (true, w / 2));
            string blush = swatch (p, "Blush", 0.00, 0.30, 0.15, 0.00);
            string berry = swatch (p, "Berry", 0.20, 0.95, 0.40, 0.15);
            string leaf = swatch (p, "Leaf", 0.60, 0.10, 0.80, 0.10);
            string cream = swatch (p, "Cream", 0.00, 0.03, 0.12, 0.00);
            string gold = swatch (p, "Gold", 0.05, 0.30, 0.90, 0.05);
            pstyle (p, "Card Greeting", StyleSheet.BASIC, SERIF, 24, 28, (int) TextAlign.CENTER, 1, berry);
            pstyle (p, "Card Line", StyleSheet.BASIC, SANS, 10, 14, (int) TextAlign.CENTER, 0, berry);
            pstyle (p, "Card Message", StyleSheet.BASIC, SERIF, 13, 20, (int) TextAlign.CENTER, 0, berry).chars.italic = 1;
            pstyle (p, "Card Back", StyleSheet.BASIC, SANS, 7, 10, (int) TextAlign.CENTER, 0, berry);
            double b = mm (3), half = w / 2;
            var outside = p.pages[0].items;
            rect (p, outside, -b, -b, half + b, h + 2 * b, cream);
            var front = rect (p, outside, half, -b, half + b, h + 2 * b, blush);
            front.fill = new Fill.linear (cream, blush, 90);
            var small = shape (p, outside, ShapeKind.STAR, half / 2 - 9, h - 80, 18, 18, gold);
            small.sides = 5;
            text (p, outside, mm (10), h - 58, half - mm (20), 30, { "Card Back|Printed on recycled paper" });
            double cx = half + half / 2;
            var c1 = ellipse (p, outside, cx - 70, 62, 140, 140, blush);
            c1.fill = new Fill.solid (ColorRef.swatch ("Blush", 70));
            var c2 = ellipse (p, outside, cx - 50, 82, 100, 100, berry);
            c2.opacity = 0.9;
            var c3 = ellipse (p, outside, cx - 18, 114, 36, 36, gold);
            string[] leaves = { "a", "b", "c", "d" };
            double[] lx = { -92, 60, -80, 52 };
            double[] ly = { 70, 70, 170, 170 };
            for (int i = 0; i < leaves.length; i++) {
                var lf = ellipse (p, outside, cx + lx[i], ly[i], 32, 18, leaf);
                lf.rotation = i % 2 == 0 ? -30 : 30;
            }
            text (p, outside, half + mm (10), 240, half - mm (20), 44, { "Card Greeting|Happy Birthday" });
            text (p, outside, half + mm (10), 290, half - mm (20), 20, { "Card Line|A little sunshine for your day" });
            c3.opacity = 1;
            var inside = p.pages[1].items;
            rect (p, inside, -b, -b, w + 2 * b, h + 2 * b, cream);
            var deco = ellipse (p, inside, half / 2 - 60, h / 2 - 60, 120, 120, blush);
            deco.opacity = 0.6;
            var dstar = shape (p, inside, ShapeKind.STAR, half / 2 - 22, h / 2 - 22, 44, 44, gold);
            dstar.sides = 6;
            dstar.star_inset = 0.5;
            var msg = text (p, inside, half + mm (12), mm (20), half - mm (24), h - mm (40), {
                "Card Message|Wishing you a year full of good books, long walks and people who make you laugh.",
                "Card Message|",
                "Card Line|With love, Anna and Leo"
            });
            msg.valign = 1;
            return p;
        }

        private static Publication menu () {
            double w = 595.28, h = 841.89;
            var s = settings (w, h, mm (20), mm (3), "a4");
            var p = Publication.create (s, 1);
            p.meta.title = _("Trattoria Luna");
            string olive = swatch (p, "Olive", 0.45, 0.30, 0.90, 0.35);
            string terracotta = swatch (p, "Terracotta", 0.10, 0.70, 0.80, 0.15);
            string linen = swatch (p, "Linen", 0.02, 0.04, 0.10, 0.00);
            string espresso = swatch (p, "Espresso", 0.40, 0.65, 0.70, 0.60);
            double m = mm (20), b = mm (3);
            double cw = w - 2 * m - 60;
            pstyle (p, "Menu Title", StyleSheet.BASIC, SERIF, 40, 44, (int) TextAlign.CENTER, 1, terracotta);
            pstyle (p, "Menu Tagline", StyleSheet.BASIC, SANS, 9, 12, (int) TextAlign.CENTER, 0, olive).chars.tracking = 300;
            p.styles.find_paragraph ("Menu Tagline").chars.caps = 1;
            var sec = pstyle (p, "Menu Section", StyleSheet.BASIC, SANS, 11, 14, (int) TextAlign.CENTER, 1, olive);
            sec.chars.caps = 1;
            sec.chars.tracking = 250;
            sec.para.space_before = 14;
            sec.para.space_after = 6;
            sec.para.keep_next = 1;
            var dish = pstyle (p, "Dish", StyleSheet.BASIC, SERIF, 12, 16, -1, 1, espresso);
            dish.para.tabs = TabStop.serialize (tabs (cw - 1, TabKind.RIGHT, "."));
            dish.para.keep_next = 1;
            var desc = pstyle (p, "Dish Note", StyleSheet.BASIC, SANS, 8.5, 11.5, -1, 0, espresso);
            desc.chars.italic = 1;
            desc.para.space_after = 5;
            desc.para.right_indent = 40;
            pstyle (p, "Menu Foot", StyleSheet.BASIC, SANS, 8, 11, (int) TextAlign.CENTER, 0, olive);
            var items = p.pages[0].items;
            rect (p, items, -b, -b, w + 2 * b, h + 2 * b, linen);
            var border = rect (p, items, mm (10), mm (10), w - mm (20), h - mm (20), ColorRef.NONE);
            border.stroke = new Stroke.with (terracotta, 1);
            var moon = ellipse (p, items, w / 2 - 16, m + 2, 32, 32, terracotta);
            var bite = ellipse (p, items, w / 2 - 6, m - 4, 30, 30, linen);
            bite.name = _("Moon Shadow");
            moon.name = _("Moon");
            text (p, items, m, m + 42, w - 2 * m, 50, { "Menu Title|Trattoria Luna" });
            text (p, items, m, m + 94, w - 2 * m, 16, { "Menu Tagline|Cucina di casa since 1987" });
            text (p, items, m + 30, m + 124, cw, h - 2 * m - 124 - 36, {
                "Menu Section|Antipasti",
                "Dish|Burrata with roasted peppers\t11",
                "Dish Note|Basil oil, sourdough crisps",
                "Dish|Fritto misto\t13",
                "Dish Note|Squid, prawns and courgette, lemon aioli",
                "Menu Section|Primi",
                "Dish|Tagliatelle al ragu\t16",
                "Dish Note|Slow-cooked beef and pork, parmigiano",
                "Dish|Risotto ai funghi\t17",
                "Dish Note|Porcini, thyme, aged pecorino",
                "Dish|Spaghetti alle vongole\t18",
                "Dish Note|Clams, white wine, chilli and parsley",
                "Menu Section|Secondi",
                "Dish|Branzino al forno\t24",
                "Dish Note|Whole sea bass, potatoes, capers and olives",
                "Dish|Pollo alla cacciatora\t21",
                "Dish Note|Braised chicken, tomato, rosemary",
                "Menu Section|Dolci",
                "Dish|Tiramisu della casa\t8",
                "Dish Note|Made each morning",
                "Dish|Panna cotta\t7",
                "Dish Note|Vanilla, seasonal fruit",
                "Dish|Affogato\t6",
                "Dish Note|Vanilla gelato, a shot of espresso",
                "Menu Section|Vini",
                "Dish|Chianti Classico, glass\t7",
                "Dish Note|Tuscany, sangiovese"
            });
            text (p, items, m, h - m - 24, w - 2 * m, 20, { "Menu Foot|Please tell us about any allergies. Bread and water are always on the house." });
            return p;
        }

        private static Publication certificate () {
            double w = 841.89, h = 595.28;
            var s = settings (w, h, mm (20), 0, "a4");
            var p = Publication.create (s, 1);
            p.meta.title = _("Certificate of Achievement");
            string navy = swatch (p, "Navy", 1.00, 0.80, 0.25, 0.30);
            string gold = swatch (p, "Gold", 0.05, 0.30, 0.90, 0.10);
            string ivory = swatch (p, "Ivory", 0.00, 0.02, 0.08, 0.00);
            string grey = swatch (p, "Warm Grey", 0.30, 0.30, 0.35, 0.20);
            pstyle (p, "Cert Kicker", StyleSheet.BASIC, SANS, 11, 14, (int) TextAlign.CENTER, 1, gold).chars.tracking = 400;
            p.styles.find_paragraph ("Cert Kicker").chars.caps = 1;
            pstyle (p, "Cert Title", StyleSheet.BASIC, SERIF, 40, 46, (int) TextAlign.CENTER, 1, navy);
            pstyle (p, "Cert Text", StyleSheet.BASIC, SERIF, 12.5, 18, (int) TextAlign.CENTER, 0, grey).chars.italic = 1;
            pstyle (p, "Cert Name", StyleSheet.BASIC, SERIF, 34, 40, (int) TextAlign.CENTER, 0, navy);
            pstyle (p, "Cert Sign", StyleSheet.BASIC, SANS, 9, 12, (int) TextAlign.CENTER, 0, grey);
            var items = p.pages[0].items;
            rect (p, items, 0, 0, w, h, ivory);
            var outer = rect (p, items, mm (10), mm (10), w - mm (20), h - mm (20), ColorRef.NONE);
            outer.stroke = new Stroke.with (navy, 4);
            var inner = rect (p, items, mm (14), mm (14), w - mm (28), h - mm (28), ColorRef.NONE);
            inner.stroke = new Stroke.with (gold, 1.2);
            double[] cxs = { mm (14), w - mm (14) };
            double[] cys = { mm (14), h - mm (14) };
            foreach (double cx in cxs) foreach (double cy in cys) {
                var d = shape (p, items, ShapeKind.POLYGON, cx - 9, cy - 9, 18, 18, gold);
                d.sides = 4;
            }
            text (p, items, 100, 80, w - 200, 20, { "Cert Kicker|Harbourside Sailing School" });
            text (p, items, 100, 110, w - 200, 56, { "Cert Title|Certificate of Achievement" });
            text (p, items, 100, 190, w - 200, 22, { "Cert Text|This certificate is proudly presented to" });
            text (p, items, 100, 222, w - 200, 50, { "Cert Name|Jonah Whitaker" });
            hline (p, items, w / 2 - 170, 276, 340, gold, 1);
            text (p, items, 150, 292, w - 300, 60, { "Cert Text|for completing the Day Skipper course with distinction, showing seamanship, calm judgement and good humour in all weathers." });
            double sy = h - 140;
            hline (p, items, 140, sy, 190, grey, 0.75);
            hline (p, items, w - 330, sy, 190, grey, 0.75);
            text (p, items, 140, sy + 6, 190, 30, { "Cert Sign|Ellen Marsh, Chief Instructor" });
            text (p, items, w - 330, sy + 6, 190, 30, { "Cert Sign|12 September 2026" });
            var seal = shape (p, items, ShapeKind.STAR, w / 2 - 44, sy - 60, 88, 88, gold);
            seal.sides = 16;
            seal.star_inset = 0.85;
            seal.shadow.enabled = true;
            seal.shadow.blur = 5;
            seal.shadow.dx = 1;
            seal.shadow.dy = 2;
            seal.shadow.opacity = 0.3;
            var core = ellipse (p, items, w / 2 - 28, sy - 44, 56, 56, navy);
            core.stroke = new Stroke.with (ivory, 1.5);
            return p;
        }

        private static Publication invitation () {
            double w = 360, h = 504;
            var s = settings (w, h, mm (12), mm (3), "5x7");
            var p = Publication.create (s, 1);
            p.meta.title = _("Invitation");
            string dusk = swatch (p, "Dusk", 0.70, 0.60, 0.10, 0.20);
            swatch (p, "Peach", 0.00, 0.35, 0.40, 0.00);
            string rose = swatch (p, "Rose", 0.05, 0.60, 0.20, 0.00);
            string shell = swatch (p, "Shell", 0.00, 0.06, 0.08, 0.00);
            swatch (p, "Moss", 0.55, 0.20, 0.75, 0.20);
            pstyle (p, "Invite Kicker", StyleSheet.BASIC, SANS, 9, 12, (int) TextAlign.CENTER, 1, rose).chars.tracking = 350;
            p.styles.find_paragraph ("Invite Kicker").chars.caps = 1;
            pstyle (p, "Invite Names", StyleSheet.BASIC, SERIF, 30, 34, (int) TextAlign.CENTER, 0, dusk).chars.italic = 1;
            pstyle (p, "Invite Text", StyleSheet.BASIC, SERIF, 11, 17, (int) TextAlign.CENTER, 0, dusk);
            pstyle (p, "Invite Detail", StyleSheet.BASIC, SANS, 10, 15, (int) TextAlign.CENTER, 1, dusk);
            pstyle (p, "Invite Small", StyleSheet.BASIC, SANS, 8, 11, (int) TextAlign.CENTER, 0, rose);
            var items = p.pages[0].items;
            double b = mm (3);
            rect (p, items, -b, -b, w + 2 * b, h + 2 * b, shell);
            double[,] petals = { { -8, -8, 110, 110 }, { 60, -8, 80, 80 }, { 256, -8, 110, 110 }, { 300, 30, 64, 64 }, { -8, 400, 110, 110 }, { 250, 392, 118, 118 } };
            string[] cols = { "Peach", "Rose", "Peach", "Moss", "Rose", "Peach" };
            for (int i = 0; i < 6; i++) {
                var e = ellipse (p, items, petals[i, 0], petals[i, 1], petals[i, 2], petals[i, 3], ColorRef.swatch (cols[i]));
                e.opacity = 0.55;
            }
            text (p, items, 40, 110, w - 80, 16, { "Invite Kicker|Together with their families" });
            text (p, items, 30, 140, w - 60, 90, { "Invite Names|Amelia Hart", "Invite Names|and Samuel Okafor" });
            text (p, items, 50, 236, w - 100, 40, { "Invite Text|request the pleasure of your company at the celebration of their marriage" });
            hline (p, items, w / 2 - 40, 290, 80, rose, 1);
            text (p, items, 40, 304, w - 80, 70, {
                "Invite Detail|Saturday, 16 May 2026 at four o'clock",
                "Invite Text|Orchard House, Little Wenham"
            });
            text (p, items, 40, 386, w - 80, 20, { "Invite Small|Dinner and dancing to follow. Kindly reply by 1 April." });
            return p;
        }

        private static Publication postcard () {
            double w = mm (148), h = mm (105);
            var s = settings (w, h, mm (7), mm (3), "postcard-a6");
            var p = Publication.create (s, 2);
            p.meta.title = _("Postcard");
            string ocean = swatch (p, "Ocean", 0.90, 0.35, 0.15, 0.05);
            string tile = swatch (p, "Tile Yellow", 0.00, 0.20, 0.85, 0.00);
            string terra = swatch (p, "Terra", 0.05, 0.60, 0.80, 0.05);
            string ink = swatch (p, "Ink", 0.70, 0.60, 0.45, 0.60);
            pstyle (p, "Postcard Small", StyleSheet.BASIC, SANS, 11, 14, -1, 1, ColorRef.PAPER).chars.tracking = 300;
            p.styles.find_paragraph ("Postcard Small").chars.caps = 1;
            pstyle (p, "Postcard Title", StyleSheet.BASIC, SERIF, 36, 38, -1, 1, ColorRef.PAPER);
            pstyle (p, "Postcard Message", StyleSheet.BASIC, SERIF, 9.5, 14, -1, 0, ink).chars.italic = 1;
            pstyle (p, "Postcard Label", StyleSheet.BASIC, SANS, 6, 8, (int) TextAlign.CENTER, 0, ink);
            double b = mm (3), m = mm (7);
            var front = p.pages[0].items;
            var img = picture (p, front, -b, -b, w + 2 * b, h + 2 * b, ocean, tile);
            img.name = _("Photo");
            var sunc = ellipse (p, front, w - 120, 30, 70, 70, tile);
            sunc.opacity = 0.9;
            var far = ellipse (p, front, -8, h - 90, 280, 98, ColorRef.swatch ("Ocean", 70));
            far.opacity = 0.9;
            var hill = ellipse (p, front, w - 250, h - 110, 258, 118, terra);
            hill.opacity = 0.95;
            text (p, front, m, m + 6, w - 2 * m - 90, 16, { "Postcard Small|Greetings from" });
            text (p, front, m, m + 26, w - 2 * m - 90, 48, { "Postcard Title|Lisbon" });
            var back = p.pages[1].items;
            double half = w / 2;
            text (p, back, m, m, half - m - 12, h - 2 * m, {
                "Postcard Message|Dear Grandma, the trams here climb hills steeper than our street and every wall is covered in blue tiles. We ate custard tarts for breakfast twice. Wish you were here. Love, Nora"
            });
            vline (p, back, half, m, h - 2 * m, ink, 0.5);
            var stamp = rect (p, back, w - m - 50, m, 50, 60, ColorRef.NONE);
            stamp.stroke = new Stroke.with (ink, 0.75);
            stamp.stroke.dash = DashKind.DASH;
            text (p, back, w - m - 50, m + 24, 50, 14, { "Postcard Label|Stamp" });
            for (int i = 0; i < 4; i++) hline (p, back, half + 12, 130 + i * 26, half - m - 12, ink, 0.5);
            return p;
        }

        private static Publication letterhead () {
            double w = 595.28, h = 841.89;
            var s = settings (w, h, mm (22), mm (3), "a4");
            s.margin_top = mm (45);
            s.margin_bottom = mm (30);
            var p = Publication.create (s, 1);
            p.meta.title = _("Letterhead");
            string plum = swatch (p, "Plum", 0.55, 0.90, 0.20, 0.25);
            string lilac = swatch (p, "Lilac", 0.25, 0.35, 0.00, 0.00);
            string graphite = swatch (p, "Graphite", 0.55, 0.45, 0.40, 0.55);
            pstyle (p, "Company", StyleSheet.BASIC, SANS, 18, 21, -1, 1, plum).chars.tracking = 40;
            pstyle (p, "Company Line", StyleSheet.BASIC, SANS, 8, 11, -1, 0, graphite);
            pstyle (p, "Address Block", StyleSheet.BASIC, SANS, 8, 11, (int) TextAlign.RIGHT, 0, graphite);
            var letter = pstyle (p, "Letter", StyleSheet.BASIC, SERIF, 10.5, 16, -1, 0, graphite);
            letter.para.space_after = 9;
            pstyle (p, "Letter Line", "Letter", null, 0, 0).para.space_after = 0;
            pstyle (p, "Legal", StyleSheet.BASIC, SANS, 7, 10, (int) TextAlign.CENTER, 0, graphite);
            var m = p.masters[0];
            double left = mm (22);
            var mark = ellipse (p, m.items, left, mm (16), 34, 34, plum);
            mark.fill = new Fill.linear (lilac, plum, 45);
            var dot = ellipse (p, m.items, left + 22, mm (16) - 4, 16, 16, lilac);
            dot.opacity = 0.9;
            text (p, m.items, left + 46, mm (16) + 1, 240, 36, {
                "Company|Aster & Vale",
                "Company Line|Landscape and garden design"
            });
            text (p, m.items, w - left - 200, mm (16), 200, 50, {
                "Address Block|7 Orchard Row, Bristol BS1 4QA",
                "Address Block|0117 555 0191",
                "Address Block|hello@asterandvale.example"
            });
            hline (p, m.items, left, mm (32), w - 2 * left, lilac, 1);
            var band = rect (p, m.items, -mm (3), h - 10, w + mm (6), 10 + mm (3), plum);
            band.fill = new Fill.linear (lilac, plum, 0);
            text (p, m.items, left, h - mm (20), w - 2 * left, 24, { "Legal|Aster & Vale Ltd, registered in England no. 08812345. VAT GB 123 4567 89." });
            var r = p.margin_rect (0);
            text (p, p.pages[0].items, r.x, r.y, r.w, r.h, {
                "Letter|3 October 2026",
                "Letter Line|Ms Priya Nair",
                "Letter Line|22 Station Road",
                "Letter|Clevedon BS21 7RT",
                "Letter|Dear Ms Nair,",
                "Letter|Thank you for showing us your garden last week. We have attached two layouts for the lower terrace: one keeps the old pear tree at the centre of a gravel court, the other opens the view to the hills with a long, low hedge of hornbeam.",
                "Letter|Both options reuse the existing stone, which keeps the cost down and lets the new walls sit comfortably beside the house. We would suggest planting in late autumn so the roots settle over winter.",
                "Letter|If you would like to talk through either plan, we can meet on site any Tuesday this month.",
                "Letter|With best wishes,",
                "Letter Line|Helena Vale",
                "Letter|Director"
            });
            return p;
        }

        private static Publication resume () {
            double w = 595.28, h = 841.89;
            var s = settings (w, h, mm (14), mm (3), "a4");
            var p = Publication.create (s, 1);
            p.meta.title = _("Resume");
            string teal = swatch (p, "Deep Teal", 0.85, 0.35, 0.45, 0.35);
            string mint = swatch (p, "Mint", 0.30, 0.00, 0.20, 0.00);
            string ink = swatch (p, "Ink", 0.70, 0.60, 0.45, 0.65);
            string sidebar_text = swatch (p, "Pale", 0.10, 0.00, 0.05, 0.00);
            pstyle (p, "CV Name", StyleSheet.BASIC, SANS, 30, 34, -1, 1, ink).chars.tracking = -10;
            pstyle (p, "CV Role", StyleSheet.BASIC, SANS, 12, 16, -1, 0, teal);
            var sec = pstyle (p, "CV Section", StyleSheet.BASIC, SANS, 10, 13, -1, 1, teal);
            sec.chars.caps = 1;
            sec.chars.tracking = 200;
            sec.para.space_before = 12;
            sec.para.space_after = 6;
            sec.para.rule_below = "0.75;" + mint + ";3";
            sec.para.keep_next = 1;
            var job = pstyle (p, "CV Job", StyleSheet.BASIC, SANS, 10.5, 14, -1, 1, ink);
            job.para.keep_next = 1;
            job.para.space_before = 4;
            var dates = pstyle (p, "CV Dates", StyleSheet.BASIC, SANS, 8.5, 12, -1, 0, teal);
            dates.chars.italic = 1;
            dates.para.keep_next = 1;
            pstyle (p, "CV Text", StyleSheet.BASIC, SANS, 9, 13, -1, 0, ink).para.space_after = 3;
            pstyle (p, "CV Bullet", "Bulleted List", SANS, 9, 13, -1, 0, ink);
            var sh = pstyle (p, "Side Heading", StyleSheet.BASIC, SANS, 9, 12, -1, 1, mint);
            sh.chars.caps = 1;
            sh.chars.tracking = 200;
            sh.para.space_before = 12;
            sh.para.space_after = 4;
            pstyle (p, "Side Text", StyleSheet.BASIC, SANS, 8.5, 12.5, -1, 0, sidebar_text).para.space_after = 2;
            var items = p.pages[0].items;
            double b = mm (3), side = 190, m = mm (14);
            var bar = rect (p, items, -b, -b, side + b, h + 2 * b, teal);
            bar.fill = new Fill.linear (teal, swatch (p, "Night Teal", 0.95, 0.50, 0.55, 0.55), 90);
            var photo = picture (p, items, side / 2 - 55, m + 6, 110, 110, mint, teal);
            photo.shape_ellipse = true;
            photo.stroke = new Stroke.with (mint, 3);
            text (p, items, 22, 170, side - 44, h - 170 - m, {
                "Side Heading|Contact",
                "Side Text|lena.brandt@mail.example",
                "Side Text|+49 555 7788 12",
                "Side Text|Hamburg, Germany",
                "Side Heading|Skills",
                "Side Text|Editorial design",
                "Side Text|Typography and grids",
                "Side Text|Prepress and colour",
                "Side Text|Photo direction",
                "Side Text|Accessible documents",
                "Side Heading|Languages",
                "Side Text|German, native",
                "Side Text|English, fluent",
                "Side Text|Spanish, conversational",
                "Side Heading|Interests",
                "Side Text|Letterpress, cycling, bread"
            });
            double x = side + 26, cw = w - x - m;
            text (p, items, x, m + 6, cw, 72, {
                "CV Name|Lena Brandt",
                "CV Role|Senior Editorial Designer"
            });
            text (p, items, x, m + 84, cw, h - m - 84 - m, {
                "CV Section|Profile",
                "CV Text|Editorial designer with twelve years of experience in magazines and annual reports. I build grids that survive deadlines, lead small teams and keep print and screen editions in step.",
                "CV Section|Experience",
                "CV Job|Art Director, Nordwind Magazine",
                "CV Dates|2019 to present, Hamburg",
                "CV Bullet|Redesigned the monthly edition and its tablet version",
                "CV Bullet|Cut prepress corrections by a third with shared styles",
                "CV Bullet|Lead a team of four designers and two photographers",
                "CV Job|Senior Designer, Hafen Reports",
                "CV Dates|2015 to 2019, Hamburg",
                "CV Bullet|Designed annual reports for listed companies",
                "CV Bullet|Introduced accessible PDF production",
                "CV Job|Designer, Studio Kranich",
                "CV Dates|2012 to 2015, Berlin",
                "CV Bullet|Books, catalogues and exhibition graphics",
                "CV Section|Education",
                "CV Job|BA Communication Design",
                "CV Dates|HAW Hamburg, 2008 to 2012",
                "CV Section|Awards",
                "CV Text|Type Directors Club certificate, 2021. European Design Award, silver, 2018."
            });
            return p;
        }

        private static int calendar_year () {
            var now = new DateTime.now_local ();
            return now.get_month () >= 9 ? now.get_year () + 1 : now.get_year ();
        }

        private static Publication calendar () {
            double w = 841.89, h = 595.28;
            var s = settings (w, h, mm (12), mm (3), "a4");
            var p = Publication.create (s, 12);
            int year = calendar_year ();
            p.meta.title = _("Calendar %d").printf (year);
            string teal = swatch (p, "Lagoon", 0.85, 0.10, 0.45, 0.05);
            string sand = swatch (p, "Sand", 0.05, 0.10, 0.30, 0.00);
            string ink = swatch (p, "Ink", 0.75, 0.60, 0.50, 0.65);
            string mist = swatch (p, "Mist", 0.08, 0.02, 0.04, 0.00);
            pstyle (p, "Month", StyleSheet.BASIC, SANS, 34, 38, -1, 1, teal);
            var year_style = pstyle (p, "Year", StyleSheet.BASIC, SANS, 14, 17, -1, 0, ink);
            year_style.chars.tracking = 200;
            var weekday_style = pstyle (p, "Weekday", StyleSheet.BASIC, SANS, 8, 10, (int) TextAlign.CENTER, 1, ColorRef.PAPER);
            weekday_style.chars.caps = 1;
            pstyle (p, "Day", StyleSheet.BASIC, SANS, 11, 13, (int) TextAlign.LEFT, 1, ink);
            double m = mm (12);
            double pic_w = w * 0.38;
            var monday = new DateTime.local (2024, 1, 1, 0, 0, 0);
            for (int mo = 1; mo <= 12; mo++) {
                var items = p.pages[mo - 1].items;
                var first = new DateTime.local (year, mo, 1, 0, 0, 0);
                var ph = picture (p, items, -mm (3), -mm (3), pic_w + mm (3), h + mm (6), sand, teal);
                ph.name = _("Photo");
                double gx = pic_w + m, gw = w - pic_w - 2 * m;
                text (p, items, gx, m - 6, gw, 58, { "Month|" + first.format ("%B") });
                text (p, items, gx, m + 54, gw, 24, { "Year|%d".printf (year) });
                int days = first.add_months (1).add_days (-1).get_day_of_month ();
                int offset = first.get_day_of_week () - 1;
                int weeks = (offset + days + 6) / 7;
                var tb = new TableItem (weeks + 1, 7);
                tb.id = p.next_id ();
                tb.x = gx;
                tb.y = m + 86;
                tb.w = gw;
                tb.h = h - tb.y - m;
                tb.layer = p.default_layer ().id;
                tb.init_cells (p);
                tb.row_h[0] = 20;
                for (int r = 1; r <= weeks; r++) tb.row_h[r] = (tb.h - 20) / weeks;
                tb.header_rows = 1;
                tb.header_fill = teal;
                tb.alt_fill = ColorRef.NONE;
                tb.border_color = ColorRef.swatch ("Lagoon", 35);
                tb.border_width = 0.5;
                for (int d = 0; d < 7; d++) {
                    var st = tb.cells[0][d].story;
                    st.paras.clear ();
                    st.paras.add (new Paragraph.with_text (monday.add_days (d).format ("%a"), "Weekday"));
                    tb.cells[0][d].valign = 1;
                }
                for (int day = 1; day <= days; day++) {
                    int idx = offset + day - 1;
                    var cell = tb.cells[1 + idx / 7][idx % 7];
                    cell.story.paras.clear ();
                    cell.story.paras.add (new Paragraph.with_text ("%d".printf (day), "Day"));
                    if (idx % 7 >= 5) cell.fill = mist;
                }
                items.add (tb);
            }
            return p;
        }

        private static Publication envelope () {
            double w = mm (220), h = mm (110);
            var s = settings (w, h, mm (10), 0, "env-dl");
            s.units = "mm";
            var p = Publication.create (s, 1);
            p.meta.title = _("Envelope");
            string forest = swatch (p, "Forest", 0.80, 0.20, 0.75, 0.30);
            string ink = swatch (p, "Ink", 0.70, 0.60, 0.50, 0.65);
            pstyle (p, "Sender", StyleSheet.BASIC, SANS, 8, 10.5, -1, 0, ink);
            pstyle (p, "Sender Name", "Sender", SANS, 9, 11, -1, 1, forest);
            pstyle (p, "Recipient", StyleSheet.BASIC, SANS, 11, 15, -1, 0, ink);
            var items = p.pages[0].items;
            double m = mm (10);
            var leaf = shape (p, items, ShapeKind.ELLIPSE, m, m, 18, 18, forest);
            leaf.name = _("Logo");
            text (p, items, m + 26, m - 2, 200, 52, {
                "Sender Name|Greenway Gardens",
                "Sender|14 Orchard Lane",
                "Sender|Bristol BS1 4DJ"
            });
            text (p, items, w * 0.45, h * 0.48, w * 0.5 - m, 70, {
                "Recipient|Ms Helen Carter",
                "Recipient|22 Riverside Walk",
                "Recipient|Oxford OX1 2AB"
            });
            var stamp = rect (p, items, w - m - 50, m, 50, 60, ColorRef.NONE);
            stamp.stroke = new Stroke.with (ink, 0.75);
            stamp.stroke.dash = DashKind.DASH;
            stamp.name = _("Stamp");
            hline (p, items, m, h - m, 120, forest, 2);
            return p;
        }

        private static Publication labels () {
            double w = mm (70), h = mm (37);
            var s = settings (w, h, mm (4), 0, "custom");
            s.impose = "nup:3x8:a4";
            s.units = "mm";
            var p = Publication.create (s, 1);
            p.meta.title = _("Address Labels");
            string berry = swatch (p, "Berry", 0.20, 0.90, 0.30, 0.10);
            string ink = swatch (p, "Ink", 0.70, 0.60, 0.50, 0.65);
            pstyle (p, "Label Name", StyleSheet.BASIC, SANS, 10, 12, -1, 1, ink);
            pstyle (p, "Label Line", StyleSheet.BASIC, SANS, 8.5, 10.5, -1, 0, ink);
            var items = p.pages[0].items;
            double m = mm (4);
            rect (p, items, 0, 0, mm (3), h, berry);
            text (p, items, m + mm (2), m, w - 2 * m - mm (2), h - 2 * m, {
                "Label Name|Helen Carter",
                "Label Line|22 Riverside Walk",
                "Label Line|Oxford OX1 2AB",
                "Label Line|United Kingdom"
            });
            ellipse (p, items, w - m - 10, m, 10, 10, berry);
            ellipse (p, items, w - m - 22, m + 2, 6, 6, ColorRef.swatch ("Berry", 50));
            hline (p, items, m + mm (2), h - m, w - 2 * m - mm (2), ColorRef.swatch ("Berry", 40), 0.5);
            return p;
        }

        private static Publication invoice () {
            double w = 595.28, h = 841.89;
            var s = settings (w, h, mm (18), 0, "a4");
            var p = Publication.create (s, 1);
            p.meta.title = _("Invoice");
            string navy = swatch (p, "Navy", 0.95, 0.75, 0.20, 0.25);
            string ink = swatch (p, "Ink", 0.70, 0.60, 0.50, 0.65);
            string pale = swatch (p, "Pale", 0.06, 0.02, 0.00, 0.00);
            var title_style = pstyle (p, "Invoice Title", StyleSheet.BASIC, SANS, 28, 32, (int) TextAlign.RIGHT, 1, navy);
            title_style.chars.tracking = 100;
            pstyle (p, "Invoice Company", StyleSheet.BASIC, SANS, 14, 17, -1, 1, navy);
            pstyle (p, "Invoice Text", StyleSheet.BASIC, SANS, 9, 13, -1, 0, ink);
            pstyle (p, "Invoice Right", "Invoice Text", null, 0, 0, (int) TextAlign.RIGHT);
            var head_style = pstyle (p, "Invoice Head", StyleSheet.BASIC, SANS, 8.5, 11, -1, 1, ColorRef.PAPER);
            head_style.chars.caps = 1;
            pstyle (p, "Invoice Total", StyleSheet.BASIC, SANS, 12, 15, (int) TextAlign.RIGHT, 1, navy);
            var items = p.pages[0].items;
            var r = p.margin_rect (0);
            text (p, items, r.x, r.y, r.w / 2, 64, {
                "Invoice Company|Northwind Studio",
                "Invoice Text|8 Harbour Street, Leith EH6 6QL",
                "Invoice Text|hello@northwind.example"
            });
            text (p, items, r.x + r.w / 2, r.y, r.w / 2, 40, { "Invoice Title|INVOICE" });
            text (p, items, r.x + r.w / 2, r.y + 44, r.w / 2, 44, {
                "Invoice Right|Invoice number 2026-041",
                "Invoice Right|Date 29 September 2026"
            });
            hline (p, items, r.x, r.y + 100, r.w, navy, 1.5);
            text (p, items, r.x, r.y + 112, r.w / 2, 60, {
                "Invoice Text|**Bill to**",
                "Invoice Text|Harbour Bakery Ltd",
                "Invoice Text|3 Quay Road, Leith EH6 7AB"
            });
            string[,] rows = {
                { "Description", "Qty", "Price", "Amount" },
                { "Logo design and brand guide", "1", "850.00", "850.00" },
                { "Menu layout, A4 two sides", "1", "320.00", "320.00" },
                { "Window sign, printed", "2", "45.00", "90.00" },
                { "Business cards, 500", "1", "60.00", "60.00" },
                { "", "", "", "" }
            };
            int nr = rows.length[0];
            var tb = new TableItem (nr, 4);
            tb.id = p.next_id ();
            tb.x = r.x;
            tb.y = r.y + 190;
            tb.w = r.w;
            tb.h = nr * 26;
            tb.layer = p.default_layer ().id;
            tb.init_cells (p);
            tb.col_w[0] = r.w - 210;
            tb.col_w[1] = 50;
            tb.col_w[2] = 80;
            tb.col_w[3] = 80;
            tb.header_fill = navy;
            tb.alt_fill = pale;
            tb.border_color = ColorRef.swatch ("Navy", 30);
            tb.border_width = 0.5;
            for (int i = 0; i < nr; i++) for (int c = 0; c < 4; c++) {
                var st = tb.cells[i][c].story;
                st.paras.clear ();
                st.paras.add (new Paragraph.with_text (rows[i, c], i == 0 ? "Invoice Head" : (c == 0 ? "Invoice Text" : "Invoice Right")));
                tb.cells[i][c].valign = 1;
            }
            items.add (tb);
            double ty = tb.y + tb.h + 16;
            text (p, items, r.x + r.w / 2, ty, r.w / 2, 54, {
                "Invoice Right|Subtotal 1,320.00",
                "Invoice Right|VAT 20% 264.00",
                "Invoice Total|Total due 1,584.00"
            });
            text (p, items, r.x, r.y + r.h - 40, r.w, 40, {
                "Invoice Text|Payment within 30 days to account GB00 NWBK 6016 1331 9268 19. Thank you for your business."
            });
            return p;
        }

        private static Publication gift_certificate () {
            double w = mm (210), h = mm (99);
            var s = settings (w, h, mm (8), mm (3), "dl-card");
            var p = Publication.create (s, 1);
            p.meta.title = _("Gift Certificate");
            string wine = swatch (p, "Wine", 0.30, 0.95, 0.60, 0.35);
            string gold = swatch (p, "Gold", 0.10, 0.30, 0.90, 0.05);
            string cream = swatch (p, "Cream", 0.00, 0.03, 0.12, 0.00);
            pstyle (p, "Gift Title", StyleSheet.BASIC, SERIF, 26, 30, -1, 1, wine);
            pstyle (p, "Gift Text", StyleSheet.BASIC, SANS, 9, 13, -1, 0, wine);
            pstyle (p, "Gift Amount", StyleSheet.BASIC, SERIF, 30, 34, (int) TextAlign.CENTER, 1, ColorRef.PAPER);
            pstyle (p, "Gift Small", StyleSheet.BASIC, SANS, 7, 9, (int) TextAlign.CENTER, 0, ColorRef.PAPER);
            var items = p.pages[0].items;
            double b = mm (3), m = mm (8);
            rect (p, items, -b, -b, w + 2 * b, h + 2 * b, cream);
            double stub = mm (55);
            var band = rect (p, items, w - stub, -b, stub + b, h + 2 * b, wine);
            band.name = _("Stub");
            var cut = vline (p, items, w - stub, 0, h, gold, 1);
            cut.stroke.dash = DashKind.DASH;
            var frame = rect (p, items, m, m, w - stub - 2 * m, h - 2 * m, ColorRef.NONE);
            frame.stroke = new Stroke.with (gold, 1.5);
            text (p, items, m + 14, m + 12, w - stub - 2 * m - 28, 36, { "Gift Title|Gift Certificate" });
            text (p, items, m + 14, m + 56, w - stub - 2 * m - 28, 110, {
                "Gift Text|For **Anna Rossi**",
                "Gift Text|From **The Book Nook**",
                "Gift Text|Redeem in store before 31 December 2026.",
                "Gift Text|Number 0142"
            });
            text (p, items, w - stub + 8, h / 2 - 30, stub - 16, 40, { "Gift Amount|€50" });
            text (p, items, w - stub + 8, h / 2 + 14, stub - 16, 30, { "Gift Small|Number 0142" });
            return p;
        }

        private static Publication sign () {
            double w = 841.89, h = 595.28;
            var s = settings (w, h, mm (15), 0, "a4");
            var p = Publication.create (s, 1);
            p.meta.title = _("Sign");
            string red = swatch (p, "Signal Red", 0.00, 0.95, 0.85, 0.05);
            string ink = swatch (p, "Ink", 0.70, 0.60, 0.50, 0.65);
            pstyle (p, "Sign Big", StyleSheet.BASIC, SANS, 120, 130, (int) TextAlign.CENTER, 1, ColorRef.PAPER);
            pstyle (p, "Sign Line", StyleSheet.BASIC, SANS, 30, 38, (int) TextAlign.CENTER, 0, ink);
            var items = p.pages[0].items;
            var r = p.margin_rect (0);
            var band = rect (p, items, r.x, r.y, r.w, 220, red);
            band.corner = CornerKind.ROUNDED;
            band.corner_radius = 18;
            var big = text (p, items, r.x, r.y + 30, r.w, 160, { "Sign Big|CLOSED" });
            big.valign = 1;
            text (p, items, r.x, r.y + 250, r.w, r.h - 250, {
                "Sign Line|Back at 2 pm",
                "Sign Line|Parcels next door at number 16"
            });
            hline (p, items, r.x + r.w / 2 - 120, r.y + r.h - 20, 240, red, 3);
            var dot = ellipse (p, items, r.x + 20, r.y + 20, 24, 24, ColorRef.PAPER);
            dot.name = _("Accent");
            return p;
        }

        private static Publication banner () {
            double w = 72 * 72, h = 24 * 72;
            var s = settings (w, h, 72, 18, "banner-2x6");
            s.units = "in";
            var p = Publication.create (s, 1);
            p.meta.title = _("Banner");
            string sun = swatch (p, "Sunflower", 0.00, 0.25, 0.95, 0.00);
            string grape = swatch (p, "Grape", 0.75, 0.95, 0.10, 0.05);
            pstyle (p, "Banner Title", StyleSheet.BASIC, SANS, 400, 440, (int) TextAlign.CENTER, 1, grape);
            pstyle (p, "Banner Line", StyleSheet.BASIC, SANS, 150, 170, (int) TextAlign.CENTER, 0, grape);
            var items = p.pages[0].items;
            double b = 18;
            var bg = rect (p, items, -b, -b, w + 2 * b, h + 2 * b, sun);
            bg.fill = new Fill.linear (sun, ColorRef.swatch ("Sunflower", 60), 90);
            var t = text (p, items, 72, 150, w - 144, 620, { "Banner Title|WELCOME HOME" });
            t.valign = 1;
            text (p, items, 72, 900, w - 144, 300, { "Banner Line|Grand opening, Saturday 10 am" });
            for (int i = 0; i < 2; i++) {
                var star = shape (p, items, ShapeKind.STAR, i == 0 ? 160 : w - 460, 1250, 300, 300, grape);
                star.opacity = 0.85;
            }
            return p;
        }

        private static Publication program () {
            double w = mm (148), h = mm (210);
            var s = settings (w, h, mm (12), mm (3), "a5");
            s.facing = true;
            s.margin_inside = mm (15);
            s.margin_outside = mm (12);
            s.margin_top = mm (18);
            s.margin_bottom = mm (16);
            var p = Publication.create (s, 4);
            p.meta.title = _("Open Source Summit Programme");
            string blue = swatch (p, "Signal Blue", 0.90, 0.60, 0.00, 0.00);
            string lime = swatch (p, "Lime", 0.35, 0.00, 0.90, 0.00);
            string night = swatch (p, "Night", 0.90, 0.80, 0.40, 0.60);
            string fog = swatch (p, "Fog", 0.06, 0.03, 0.00, 0.00);
            pstyle (p, "Prog Title", StyleSheet.BASIC, SANS, 30, 32, -1, 1, ColorRef.PAPER).chars.tracking = -20;
            pstyle (p, "Prog Date", StyleSheet.BASIC, SANS, 11, 15, -1, 1, lime).chars.caps = 1;
            p.styles.find_paragraph ("Prog Date").chars.tracking = 150;
            pstyle (p, "Prog Heading", "Heading 2", SANS, 16, 20, -1, 1, blue).para.space_after = 6;
            pstyle (p, "Prog Body", "Body Text", SANS, 9, 13.5, (int) TextAlign.LEFT, 0, night).para.space_after = 6;
            pstyle (p, "Cell Head", StyleSheet.BASIC, SANS, 8, 10, -1, 1, ColorRef.PAPER).chars.caps = 1;
            pstyle (p, "Cell Text", StyleSheet.BASIC, SANS, 8, 10, -1, 0, night);
            pstyle (p, "Running Head", StyleSheet.BASIC, SANS, 7, 9, -1, 1, blue).chars.caps = 1;
            pstyle (p, "Folio", StyleSheet.BASIC, SANS, 8, 10, (int) TextAlign.RIGHT, 1, blue);
            pstyle (p, "Folio Left", "Folio", null, 0, 0, (int) TextAlign.LEFT);
            var m = p.masters[0];
            double fy = h - s.margin_bottom + 14;
            text (p, m.items, w - s.margin_outside - 50, fy, 50, 14, { "Folio|{page}" });
            text (p, m.left_items, s.margin_outside, fy, 50, 14, { "Folio Left|{page}" });
            text (p, m.items, s.margin_inside, s.margin_top - 22, 200, 12, { "Running Head|Open Source Summit 2026" });
            text (p, m.left_items, s.margin_outside, s.margin_top - 22, 200, 12, { "Running Head|Programme" });
            hline (p, m.items, s.margin_inside, s.margin_top - 8, w - s.margin_inside - s.margin_outside, lime, 1);
            hline (p, m.left_items, s.margin_outside, s.margin_top - 8, w - s.margin_inside - s.margin_outside, lime, 1);
            var cover = p.pages[0];
            cover.hide_master = true;
            double b = mm (3);
            var bg = rect (p, cover.items, -b, -b, w + b, h + 2 * b, night);
            bg.fill = new Fill.linear (blue, night, 100);
            var hx = shape (p, cover.items, ShapeKind.POLYGON, w - 212, 40, 220, 220, lime);
            hx.sides = 6;
            hx.opacity = 0.85;
            var hx2 = shape (p, cover.items, ShapeKind.POLYGON, w - 120, 220, 120, 120, ColorRef.NONE);
            hx2.sides = 6;
            hx2.stroke = new Stroke.with (ColorRef.PAPER, 2);
            text (p, cover.items, mm (12), h - 250, w - mm (24), 110, { "Prog Title|Open Source Summit" });
            text (p, cover.items, mm (12), h - 140, w - mm (24), 50, {
                "Prog Date|12 to 13 June 2026",
                "Prog Date|Congress Hall, Tallinn"
            });
            var r1 = p.margin_rect (1);
            text (p, p.pages[1].items, r1.x, r1.y, r1.w, r1.h - 166, {
                "Prog Heading|Welcome",
                "Prog Body|Two days, three rooms and more than forty talks about building software in the open. Whether you maintain a large project or have just sent your first patch, there is a session for you.",
                "Prog Body|Doors open at eight thirty each morning. Coffee is served in the foyer, lunch in the garden hall, and the hallway track runs all day in the library corner.",
                "Prog Heading|Good to know",
                "Prog Body|Wi-Fi: summit-guest. Talks are recorded and published within a week. Please wear your badge at all times and follow the code of conduct printed on the back page.",
                "Prog Body|Quiet room: second floor, room 204. First aid: ask any volunteer in a lime shirt.",
                "Prog Heading|Getting there",
                "Prog Body|Trams 2 and 4 stop outside the hall. Bicycle racks are behind the east entrance, and the harbour car park is a five minute walk."
            });
            var kp = picture (p, p.pages[1].items, r1.x, r1.y + r1.h - 150, r1.w, 150, lime, blue);
            kp.corner = CornerKind.ROUNDED;
            kp.corner_radius = 6;
            kp.name = _("Keynote Photo");
            var r2 = p.margin_rect (2);
            var pg2 = p.pages[2].items;
            text (p, pg2, r2.x, r2.y, r2.w, 26, { "Prog Heading|Friday schedule" });
            string[,] rows = {
                { "Time", "Session", "Room" },
                { "09:00", "Opening keynote: twenty years of shared code", "Main" },
                { "10:00", "Funding maintainers without burning out", "Main" },
                { "10:00", "Writing a font rasteriser from scratch", "Lab" },
                { "11:30", "Accessible desktops for everyone", "Main" },
                { "11:30", "Hands-on: packaging with reproducible builds", "Lab" },
                { "13:00", "Lunch in the garden hall", "Garden" },
                { "14:00", "Security audits on a volunteer budget", "Main" },
                { "15:30", "Lightning talks", "Main" },
                { "17:00", "Community awards and closing", "Main" }
            };
            int nr = rows.length[0];
            var tb = new TableItem (nr, 3);
            tb.id = p.next_id ();
            tb.x = r2.x;
            tb.y = r2.y + 32;
            tb.w = r2.w;
            tb.h = nr * 30;
            tb.layer = p.default_layer ().id;
            tb.init_cells (p);
            tb.col_w[0] = 42;
            tb.col_w[2] = 44;
            tb.col_w[1] = r2.w - 86;
            tb.header_fill = blue;
            tb.alt_fill = fog;
            tb.border_color = ColorRef.swatch ("Signal Blue", 30);
            tb.border_width = 0.5;
            for (int r = 0; r < nr; r++) for (int c = 0; c < 3; c++) {
                var st = tb.cells[r][c].story;
                st.paras.clear ();
                st.paras.add (new Paragraph.with_text (rows[r, c], r == 0 ? "Cell Head" : "Cell Text"));
                tb.cells[r][c].valign = 1;
            }
            pg2.add (tb);
            var note = rect (p, pg2, r2.x, tb.y + tb.h + 16, r2.w, 60, fog);
            note.corner = CornerKind.ROUNDED;
            note.corner_radius = 6;
            var nt = text (p, pg2, r2.x + 10, tb.y + tb.h + 22, r2.w - 20, 48, { "Prog Body|Saturday brings workshops all day in the Lab and the contributor sprint in the library. Sign up at the registration desk." });
            nt.valign = 1;
            var r3 = p.margin_rect (3);
            var pg3 = p.pages[3].items;
            var map = picture (p, pg3, r3.x, r3.y, r3.w, 180, fog, lime);
            map.corner = CornerKind.ROUNDED;
            map.corner_radius = 6;
            map.name = _("Venue Map");
            text (p, pg3, r3.x, r3.y + 196, r3.w, r3.h - 196, {
                "Prog Heading|Code of conduct",
                "Prog Body|Be kind, be patient and assume good intent. Harassment of any kind is not welcome. If something makes you uncomfortable, talk to a volunteer or write to safety@summit.example.",
                "Prog Heading|Thank you",
                "Prog Body|The summit is run by volunteers and supported by the city library, the technical university and the members of the association."
            });
            return p;
        }
    }
}
