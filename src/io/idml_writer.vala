namespace Singularity.Apps.Publish {

    public class IdmlWriter {
        public const string PKG = "http://ns.adobe.com/AdobeInDesign/idml/1.0/packaging";
        private Publication pub;
        private LayoutCache cache;
        private Gee.HashMap<string, string> color_ids = new Gee.HashMap<string, string> ();
        private Gee.ArrayList<string> colors_xml = new Gee.ArrayList<string> ();
        private Gee.HashSet<int> stories_used = new Gee.HashSet<int> ();
        private int serial = 1000;
        private Gee.ArrayList<string> table_story_files = new Gee.ArrayList<string> ();
        private Gee.ArrayList<string> table_story_xml = new Gee.ArrayList<string> ();

        public IdmlWriter (Publication pub) {
            this.pub = pub;
            cache = new LayoutCache (pub);
        }

        private static string n (double v) {
            return XmlOut.num (Math.round (v * 1000) / 1000);
        }

        private string uid () {
            return "u%x".printf (serial++);
        }

        private static string style_self (string kind, string name) {
            return "%s/%s".printf (kind, name.replace ("/", "\\/").replace (":", "\\:"));
        }

        private string color (string spec) {
            if (spec == ColorRef.NONE) return "Swatch/None";
            string name;
            double tint = 100;
            if (ColorRef.is_swatch (spec)) {
                name = ColorRef.swatch_name (spec);
                tint = ColorRef.tint_of (spec);
            } else {
                name = spec.has_prefix ("cmyk:") ? "C" + spec.substring (5).replace (",", " ") : pub.resolve_screen (spec).to_hex ().up ();
            }
            string base_self;
            if (name == "Paper" || name == "Black" || name == "Registration") base_self = "Color/" + name;
            else {
                string key = "c:" + name;
                if (!color_ids.has_key (key)) {
                    string self = "Color/" + name.replace ("/", "_");
                    var sw = ColorRef.is_swatch (spec) ? pub.swatch (name) : null;
                    if (sw != null && sw.model == ColorModel.RGB) {
                        colors_xml.add ("<Color Self=\"%s\" Model=\"%s\" Space=\"RGB\" ColorValue=\"%s %s %s\" Name=\"%s\" ColorEditable=\"true\" ColorRemovable=\"true\" Visible=\"true\"/>".printf (XmlOut.esc (self), sw.spot ? "Spot" : "Process", n (sw.r * 255), n (sw.g * 255), n (sw.b * 255), XmlOut.esc (name)));
                    } else if (sw != null) {
                        colors_xml.add ("<Color Self=\"%s\" Model=\"%s\" Space=\"CMYK\" ColorValue=\"%s %s %s %s\" Name=\"%s\" ColorEditable=\"true\" ColorRemovable=\"true\" Visible=\"true\"/>".printf (XmlOut.esc (self), sw.spot ? "Spot" : "Process", n (sw.c * 100), n (sw.m * 100), n (sw.y * 100), n (sw.k * 100), XmlOut.esc (name)));
                    } else if (spec.has_prefix ("cmyk:")) {
                        string[] f = spec.substring (5).split (",");
                        colors_xml.add ("<Color Self=\"%s\" Model=\"Process\" Space=\"CMYK\" ColorValue=\"%s %s %s %s\" Name=\"%s\" Visible=\"true\"/>".printf (XmlOut.esc (self), n (Units.parse_num (f[0], 0) * 100), n (Units.parse_num (f[1], 0) * 100), n (Units.parse_num (f[2], 0) * 100), n (Units.parse_num (f[3], 0) * 100), XmlOut.esc (name)));
                    } else {
                        var c = pub.resolve_screen (spec);
                        colors_xml.add ("<Color Self=\"%s\" Model=\"Process\" Space=\"RGB\" ColorValue=\"%s %s %s\" Name=\"%s\" Visible=\"true\"/>".printf (XmlOut.esc (self), n (c.r * 255), n (c.g * 255), n (c.b * 255), XmlOut.esc (name)));
                    }
                    color_ids[key] = self;
                }
                base_self = color_ids[key];
            }
            if (tint >= 99.99) return base_self;
            string tkey = "t:%s:%s".printf (base_self, n (tint));
            if (!color_ids.has_key (tkey)) {
                string self = "Tint/%s %s%%".printf (base_self.substring (6), n (tint));
                colors_xml.add ("<Tint Self=\"%s\" BaseColor=\"%s\" TintValue=\"%s\"/>".printf (XmlOut.esc (self), XmlOut.esc (base_self), n (tint)));
                color_ids[tkey] = self;
            }
            return color_ids[tkey];
        }

        private string transform (Item it) {
            double a = it.rotation * Math.PI / 180;
            double sx = it.flip_h ? -1 : 1, sy = it.flip_v ? -1 : 1;
            var c = it.center ();
            return "%s %s %s %s %s %s".printf (n (Math.cos (a) * sx), n (Math.sin (a) * sx), n (-Math.sin (a) * sy), n (Math.cos (a) * sy), n (c.x), n (c.y));
        }

        private void path (StringBuilder sb, Gee.List<Point?> pts, double w, double h, bool open) {
            sb.append ("<Properties><PathGeometry><GeometryPathType PathOpen=\"%s\"><PathPointArray>".printf (open ? "true" : "false"));
            foreach (var p in pts) {
                string xy = "%s %s".printf (n (p.x - w / 2), n (p.y - h / 2));
                sb.append ("<PathPointType Anchor=\"%s\" LeftDirection=\"%s\" RightDirection=\"%s\"/>".printf (xy, xy, xy));
            }
            sb.append ("</PathPointArray></GeometryPathType></PathGeometry></Properties>");
        }

        private Gee.ArrayList<Point?> box_points (double w, double h) {
            var l = new Gee.ArrayList<Point?> ();
            l.add (Point (0, 0));
            l.add (Point (0, h));
            l.add (Point (w, h));
            l.add (Point (w, 0));
            return l;
        }

        private Gee.ArrayList<Point?> ellipse_points (double w, double h) {
            var l = new Gee.ArrayList<Point?> ();
            for (int i = 0; i < 32; i++) {
                double t = 2 * Math.PI * i / 32;
                l.add (Point (w / 2 + w / 2 * Math.cos (t), h / 2 + h / 2 * Math.sin (t)));
            }
            return l;
        }

        private string common (Item it, string self) {
            var sb = new StringBuilder ();
            sb.append (" Self=\"%s\"".printf (self));
            if (it.name != "") sb.append (" Name=\"%s\"".printf (XmlOut.esc (it.name)));
            sb.append (" ItemLayer=\"u%x\"".printf (it.layer));
            sb.append (" ItemTransform=\"%s\"".printf (transform (it)));
            sb.append (" FillColor=\"%s\"".printf (it.fill.kind == FillKind.SOLID ? color (it.fill.color) : ((it.fill.kind == FillKind.LINEAR || it.fill.kind == FillKind.RADIAL) && it.fill.stops.size > 0 ? color (it.fill.stops[0].color) : "Swatch/None")));
            if (it.stroke.visible ()) sb.append (" StrokeColor=\"%s\" StrokeWeight=\"%s\"".printf (color (it.stroke.color), n (it.stroke.width)));
            else sb.append (" StrokeColor=\"Swatch/None\" StrokeWeight=\"0\"");
            if (it.object_style != "") sb.append (" AppliedObjectStyle=\"%s\"".printf (XmlOut.esc (style_self ("ObjectStyle", it.object_style))));
            if (it.locked) sb.append (" Locked=\"true\"");
            if (it.hidden) sb.append (" Visible=\"false\"");
            if (it.nonprinting) sb.append (" Nonprinting=\"true\"");
            if (it.corner == CornerKind.ROUNDED && it.corner_radius > 0) sb.append (" TopLeftCornerOption=\"RoundedCorner\" TopRightCornerOption=\"RoundedCorner\" BottomLeftCornerOption=\"RoundedCorner\" BottomRightCornerOption=\"RoundedCorner\" TopLeftCornerRadius=\"%s\" TopRightCornerRadius=\"%s\" BottomLeftCornerRadius=\"%s\" BottomRightCornerRadius=\"%s\"".printf (n (it.corner_radius), n (it.corner_radius), n (it.corner_radius), n (it.corner_radius)));
            return sb.str;
        }

        private string wrap_pref (Item it) {
            if (!it.wrap.wraps ()) return "";
            string mode = it.wrap == WrapMode.JUMP ? "JumpObjectTextWrap" : (it.wrap == WrapMode.CONTOUR || it.wrap == WrapMode.THROUGH ? "Contour" : "BoundingBoxTextWrap");
            string o = n (it.wrap_offset);
            return "<TextWrapPreference TextWrapMode=\"%s\" TextWrapOffset=\"%s %s %s %s\"/>".printf (mode, o, o, o, o);
        }

        private void item (StringBuilder sb, Item it) {
            string self = "u%x".printf (it.id);
            var g = it as GroupItem;
            if (g != null) {
                sb.append ("<Group Self=\"%s\" ItemLayer=\"u%x\" ItemTransform=\"1 0 0 1 0 0\">".printf (self, g.layer));
                foreach (var c in g.children) item (sb, c);
                sb.append ("</Group>");
                return;
            }
            var t = it as TextFrame;
            if (t != null) {
                var st = pub.story (t.story);
                stories_used.add (t.story);
                int idx = st.frames.index_of (t.id);
                string prev = idx > 0 ? "u%x".printf (st.frames[idx - 1]) : "n";
                string next = idx >= 0 && idx < st.frames.size - 1 ? "u%x".printf (st.frames[idx + 1]) : "n";
                sb.append ("<TextFrame%s ParentStory=\"u%x\" PreviousTextFrame=\"%s\" NextTextFrame=\"%s\" ContentType=\"TextType\">".printf (common (it, self), t.story, prev, next));
                path (sb, box_points (t.w, t.h), t.w, t.h, false);
                string vj = t.valign == 1 ? "CenterAlign" : (t.valign == 2 ? "BottomAlign" : (t.valign == 3 ? "JustifyAlign" : "TopAlign"));
                sb.append ("<TextFramePreference TextColumnCount=\"%d\" TextColumnGutter=\"%s\" InsetSpacing=\"%s %s %s %s\" VerticalJustification=\"%s\" IgnoreWrap=\"%s\"/>".printf (t.columns, n (t.gutter), n (t.inset_top), n (t.inset_left), n (t.inset_bottom), n (t.inset_right), vj, t.ignore_wrap ? "true" : "false"));
                sb.append (wrap_pref (it));
                sb.append ("</TextFrame>");
                return;
            }
            var im = it as ImageFrame;
            if (im != null) {
                sb.append ("<Rectangle%s ContentType=\"GraphicType\">".printf (common (it, self)));
                path (sb, im.shape_ellipse || im.clip_shape == "ellipse" ? ellipse_points (im.w, im.h) : box_points (im.w, im.h), im.w, im.h, false);
                sb.append (wrap_pref (it));
                var inf = ImageStore.get_default ().info (pub, im);
                var data = ImageStore.get_default ().bytes_for (pub, im);
                if (inf != null) {
                    var pl = ImageStore.place (im, inf);
                    double iw = inf.width, ih = inf.height;
                    double gw = iw * 72 / inf.dpi, gh = ih * 72 / inf.dpi;
                    double sx = pl.sx * inf.dpi / 72, sy = pl.sy * inf.dpi / 72;
                    sb.append ("<Image Self=\"%s\" ItemTransform=\"%s 0 0 %s %s %s\">".printf (uid (), n (sx), n (sy), n (pl.ox - im.w / 2), n (pl.oy - im.h / 2)));
                    sb.append ("<Properties><GraphicBounds Left=\"0\" Top=\"0\" Right=\"%s\" Bottom=\"%s\"/>".printf (n (gw), n (gh)));
                    if (im.link == "" && data != null) sb.append ("<Contents><![CDATA[%s]]></Contents>".printf (Base64.encode (data)));
                    sb.append ("</Properties>");
                    if (im.link != "") {
                        string path_s = ImageStore.resolve_link (pub, im.link);
                        string uri;
                        try {
                            uri = Filename.to_uri (path_s);
                        } catch (Error e) {
                            uri = "file:" + path_s;
                        }
                        sb.append ("<Link Self=\"%s\" LinkResourceURI=\"%s\" StoredState=\"Normal\"/>".printf (uid (), XmlOut.esc (uri)));
                    }
                    sb.append ("</Image>");
                }
                sb.append ("</Rectangle>");
                return;
            }
            var s = it as ShapeItem;
            if (s != null) {
                switch (s.shape) {
                    case ShapeKind.RECT:
                        sb.append ("<Rectangle%s>".printf (common (it, self)));
                        path (sb, box_points (s.w, s.h), s.w, s.h, false);
                        sb.append (wrap_pref (it));
                        sb.append ("</Rectangle>");
                        return;
                    case ShapeKind.ELLIPSE:
                        sb.append ("<Oval%s>".printf (common (it, self)));
                        path (sb, ellipse_points (s.w, s.h), s.w, s.h, false);
                        sb.append (wrap_pref (it));
                        sb.append ("</Oval>");
                        return;
                    case ShapeKind.LINE:
                        sb.append ("<GraphicLine%s>".printf (common (it, self)));
                        path (sb, s.local_points (), s.w, s.h, true);
                        sb.append ("</GraphicLine>");
                        return;
                    default:
                        sb.append ("<Polygon%s>".printf (common (it, self)));
                        path (sb, s.local_points (), s.w, s.h, s.shape == ShapeKind.PATH && !s.closed);
                        sb.append (wrap_pref (it));
                        sb.append ("</Polygon>");
                        return;
                }
            }
            var tb = it as TableItem;
            if (tb != null) {
                string sid = "ut%x".printf (tb.id);
                sb.append ("<TextFrame%s ParentStory=\"%s\" PreviousTextFrame=\"n\" NextTextFrame=\"n\" ContentType=\"TextType\">".printf (common (it, self), sid));
                path (sb, box_points (tb.w, tb.h), tb.w, tb.h, false);
                sb.append ("<TextFramePreference TextColumnCount=\"1\" InsetSpacing=\"0 0 0 0\"/>");
                sb.append (wrap_pref (it));
                sb.append ("</TextFrame>");
                var ts = new StringBuilder ("<?xml version=\"1.0\" encoding=\"UTF-8\" standalone=\"yes\"?>\n");
                ts.append ("<idPkg:Story xmlns:idPkg=\"%s\" DOMVersion=\"8.0\"><Story Self=\"%s\"><ParagraphStyleRange AppliedParagraphStyle=\"ParagraphStyle/$ID/NormalParagraphStyle\"><CharacterStyleRange AppliedCharacterStyle=\"CharacterStyle/$ID/[No character style]\">".printf (PKG, sid));
                ts.append (table_xml (tb));
                ts.append ("</CharacterStyleRange></ParagraphStyleRange></Story></idPkg:Story>");
                table_story_files.add ("Stories/Story_%s.xml".printf (sid));
                table_story_xml.add (ts.str);
            }
        }

        private string table_xml (TableItem tb) {
            var sb = new StringBuilder ();
            int hdr = tb.header_rows.clamp (0, tb.rows);
            sb.append ("<Table Self=\"%s\" HeaderRowCount=\"%d\" BodyRowCount=\"%d\" ColumnCount=\"%d\"".printf (uid (), hdr, tb.rows - hdr, tb.cols));
            if (tb.table_style != "") sb.append (" AppliedTableStyle=\"%s\"".printf (XmlOut.esc (style_self ("TableStyle", tb.table_style))));
            sb.append (">");
            for (int r = 0; r < tb.rows; r++) sb.append ("<Row Self=\"%s\" Name=\"%d\" SingleRowHeight=\"%s\"/>".printf (uid (), r, n (tb.row_h[r])));
            for (int c = 0; c < tb.cols; c++) sb.append ("<Column Self=\"%s\" Name=\"%d\" SingleColumnWidth=\"%s\"/>".printf (uid (), c, n (tb.col_w[c])));
            for (int r = 0; r < tb.rows; r++) for (int c = 0; c < tb.cols; c++) {
                var cell = tb.cells[r][c];
                if (cell.covered) continue;
                sb.append ("<Cell Self=\"%s\" Name=\"%d:%d\" RowSpan=\"%d\" ColumnSpan=\"%d\"".printf (uid (), c, r, cell.row_span, cell.col_span));
                if (cell.fill != ColorRef.NONE && cell.fill != "") sb.append (" FillColor=\"%s\"".printf (XmlOut.esc (color (cell.fill))));
                if (cell.valign > 0) sb.append (" VerticalJustification=\"%s\"".printf (cell.valign == 1 ? "CenterAlign" : "BottomAlign"));
                if (cell.cell_style != "") sb.append (" AppliedCellStyle=\"%s\"".printf (XmlOut.esc (style_self ("CellStyle", cell.cell_style))));
                sb.append (">");
                sb.append (paras_xml (cell.story, new FieldContext (pub)));
                sb.append ("</Cell>");
            }
            sb.append ("</Table>");
            return sb.str;
        }

        private string char_attrs (CharFormat f) {
            var sb = new StringBuilder ();
            if (!f.size.is_nan ()) sb.append (" PointSize=\"%s\"".printf (n (f.size)));
            string fs = f.bold == 1 && f.italic == 1 ? "Bold Italic" : (f.bold == 1 ? "Bold" : (f.italic == 1 ? "Italic" : (f.bold == 0 || f.italic == 0 ? "Regular" : "")));
            if (fs != "") sb.append (" FontStyle=\"%s\"".printf (fs));
            if (f.color != null) sb.append (" FillColor=\"%s\"".printf (XmlOut.esc (color (f.color))));
            if (f.underline >= 0) sb.append (" Underline=\"%s\"".printf (f.underline == 1 ? "true" : "false"));
            if (f.strike >= 0) sb.append (" StrikeThru=\"%s\"".printf (f.strike == 1 ? "true" : "false"));
            if (f.caps == 1) sb.append (" Capitalization=\"AllCaps\"");
            if (f.caps == 2) sb.append (" Capitalization=\"SmallCaps\"");
            if (f.position == 1) sb.append (" Position=\"Superscript\"");
            if (f.position == 2) sb.append (" Position=\"Subscript\"");
            if (!f.tracking.is_nan ()) sb.append (" Tracking=\"%s\"".printf (n (f.tracking)));
            if (!f.baseline_shift.is_nan ()) sb.append (" BaselineShift=\"%s\"".printf (n (f.baseline_shift)));
            return sb.str;
        }

        private string para_attrs (ParaFormat p) {
            var sb = new StringBuilder ();
            string[] just = { "LeftAlign", "CenterAlign", "RightAlign", "LeftJustified", "FullyJustified" };
            if (p.align >= 0) sb.append (" Justification=\"%s\"".printf (just[p.align.clamp (0, 4)]));
            if (!p.left_indent.is_nan ()) sb.append (" LeftIndent=\"%s\"".printf (n (p.left_indent)));
            if (!p.right_indent.is_nan ()) sb.append (" RightIndent=\"%s\"".printf (n (p.right_indent)));
            if (!p.first_indent.is_nan ()) sb.append (" FirstLineIndent=\"%s\"".printf (n (p.first_indent)));
            if (!p.space_before.is_nan ()) sb.append (" SpaceBefore=\"%s\"".printf (n (p.space_before)));
            if (!p.space_after.is_nan ()) sb.append (" SpaceAfter=\"%s\"".printf (n (p.space_after)));
            if (p.drop_lines >= 2) sb.append (" DropCapLines=\"%d\" DropCapCharacters=\"%d\"".printf (p.drop_lines, int.max (1, p.drop_chars)));
            if (p.keep_next == 1) sb.append (" KeepWithNext=\"1\"");
            if (p.hyphenate >= 0) sb.append (" Hyphenation=\"%s\"".printf (p.hyphenate == 1 ? "true" : "false"));
            if (p.list_type == 1) sb.append (" BulletsAndNumberingListType=\"BulletList\"");
            if (p.list_type == 2) sb.append (" BulletsAndNumberingListType=\"NumberedList\"");
            return sb.str;
        }

        private string leading_props (ParaFormat p) {
            if (p.leading.is_nan () || p.leading <= 0.01) return "";
            return "<Leading type=\"unit\">%s</Leading>".printf (n (p.leading));
        }

        private string paras_xml (Story st, FieldContext fc) {
            var sb = new StringBuilder ();
            for (int i = 0; i < st.paras.size; i++) {
                var p = st.paras[i];
                sb.append ("<ParagraphStyleRange AppliedParagraphStyle=\"%s\"%s>".printf (XmlOut.esc (style_self ("ParagraphStyle", p.style)), para_attrs (p.fmt)));
                string lp = leading_props (p.fmt);
                if (lp != "") sb.append ("<Properties>%s</Properties>".printf (lp));
                for (int k = 0; k < p.runs.size; k++) {
                    var r = p.runs[k];
                    if (r.note != null && !Footnotes.is_endnote (r)) {
                        sb.append ("<CharacterStyleRange AppliedCharacterStyle=\"CharacterStyle/$ID/[No character style]\"><Footnote>");
                        var inner = r.note.clone ();
                        if (inner.paras.size > 0) inner.paras[0].runs.insert (0, new Run ("\t"));
                        sb.append (paras_xml (inner, fc).replace ("<Content>\t", "<Content><?ACE 4?>\t"));
                        sb.append ("</Footnote>");
                        if (k == p.runs.size - 1 && i < st.paras.size - 1) sb.append ("<Br/>");
                        sb.append ("</CharacterStyleRange>");
                        continue;
                    }
                    if (r.anchor != null) {
                        sb.append ("<CharacterStyleRange AppliedCharacterStyle=\"CharacterStyle/$ID/[No character style]\">");
                        var asb = new StringBuilder ();
                        item (asb, r.anchor);
                        string axml = asb.str;
                        int gt = axml.index_of (">");
                        bool selfclosing = gt > 0 && axml[gt - 1] == '/';
                        string setting = r.anchor_spec != null && !r.anchor_spec.inline () ? "<AnchoredObjectSetting AnchoredPosition=\"Anchored\" HorizontalReferencePoint=\"%s\" AnchorXoffset=\"%s\" AnchorYoffset=\"%s\"/>".printf (r.anchor_spec.x_ref == 1 ? "TextFrame" : "AnchorLocation", n (r.anchor_spec.x_offset), n (r.anchor_spec.y_offset)) : "<AnchoredObjectSetting AnchoredPosition=\"InlinePosition\" AnchorYoffset=\"%s\"/>".printf (n (r.anchor_spec != null ? -r.anchor_spec.y_offset : 0));
                        if (!selfclosing && gt > 0) axml = axml.substring (0, gt + 1) + setting + axml.substring (gt + 1);
                        sb.append (axml);
                        if (k == p.runs.size - 1 && i < st.paras.size - 1) sb.append ("<Br/>");
                        sb.append ("</CharacterStyleRange>");
                        continue;
                    }
                    if (r.field.has_prefix (IndexMarker.PREFIX)) continue;
                    string text = r.field != "" ? fc.resolve (r.field) : r.text;
                    string cs = r.cstyle != "" ? style_self ("CharacterStyle", r.cstyle) : "CharacterStyle/$ID/[No character style]";
                    sb.append ("<CharacterStyleRange AppliedCharacterStyle=\"%s\"%s>".printf (XmlOut.esc (cs), char_attrs (r.fmt)));
                    if (r.fmt.font != null) sb.append ("<Properties><AppliedFont type=\"string\">%s</AppliedFont></Properties>".printf (XmlOut.esc (r.fmt.font)));
                    string[] lines = text.replace ("​", "").split (" ");
                    for (int li = 0; li < lines.length; li++) {
                        if (li > 0) sb.append ("<Content>&#x2028;</Content>");
                        if (lines[li] != "") sb.append ("<Content>%s</Content>".printf (XmlOut.esc (lines[li])));
                    }
                    if (k == p.runs.size - 1 && i < st.paras.size - 1) sb.append ("<Br/>");
                    sb.append ("</CharacterStyleRange>");
                }
                if (p.runs.size == 0 && i < st.paras.size - 1) sb.append ("<CharacterStyleRange AppliedCharacterStyle=\"CharacterStyle/$ID/[No character style]\"><Br/></CharacterStyleRange>");
                sb.append ("</ParagraphStyleRange>");
            }
            return sb.str;
        }

        public string story_xml (Story st) {
            var sb = new StringBuilder ("<?xml version=\"1.0\" encoding=\"UTF-8\" standalone=\"yes\"?>\n");
            sb.append ("<idPkg:Story xmlns:idPkg=\"%s\" DOMVersion=\"8.0\"><Story Self=\"u%x\" AppliedTOCStyle=\"n\" TrackChanges=\"false\" StoryTitle=\"$ID/\" AppliedNamedGrid=\"n\">".printf (PKG, st.id));
            var fc = new FieldContext (pub);
            int page = -1;
            var frames = pub.thread_frames (st.id);
            if (frames.size > 0) {
                var r = pub.find_item (frames[0].id);
                if (r != null && r.page != null) page = pub.pages.index_of (r.page);
            }
            fc.page_index = page;
            sb.append (paras_xml (st, fc));
            sb.append ("</Story></idPkg:Story>");
            return sb.str;
        }

        public string styles_xml () {
            var sb = new StringBuilder ("<?xml version=\"1.0\" encoding=\"UTF-8\" standalone=\"yes\"?>\n");
            sb.append ("<idPkg:Styles xmlns:idPkg=\"%s\" DOMVersion=\"8.0\">".printf (PKG));
            sb.append ("<RootCharacterStyleGroup Self=\"u79\"><CharacterStyle Self=\"CharacterStyle/$ID/[No character style]\" Name=\"$ID/[No character style]\"/>");
            foreach (var cs in pub.styles.character) {
                sb.append ("<CharacterStyle Self=\"%s\" Name=\"%s\"%s>".printf (XmlOut.esc (style_self ("CharacterStyle", cs.name)), XmlOut.esc (cs.name), char_attrs (cs.chars)));
                var props = new StringBuilder ();
                if (cs.based_on != "") props.append ("<BasedOn type=\"object\">%s</BasedOn>".printf (XmlOut.esc (style_self ("CharacterStyle", cs.based_on))));
                if (cs.chars.font != null) props.append ("<AppliedFont type=\"string\">%s</AppliedFont>".printf (XmlOut.esc (cs.chars.font)));
                if (props.len > 0) sb.append ("<Properties>%s</Properties>".printf (props.str));
                sb.append ("</CharacterStyle>");
            }
            sb.append ("</RootCharacterStyleGroup>");
            sb.append ("<RootParagraphStyleGroup Self=\"u78\"><ParagraphStyle Self=\"ParagraphStyle/$ID/NormalParagraphStyle\" Name=\"$ID/NormalParagraphStyle\"/>");
            foreach (var ps in pub.styles.paragraph) {
                sb.append ("<ParagraphStyle Self=\"%s\" Name=\"%s\"%s%s>".printf (XmlOut.esc (style_self ("ParagraphStyle", ps.name)), XmlOut.esc (ps.name), para_attrs (ps.para), char_attrs (ps.chars)));
                var props = new StringBuilder ();
                if (ps.based_on != "") props.append ("<BasedOn type=\"object\">%s</BasedOn>".printf (XmlOut.esc (style_self ("ParagraphStyle", ps.based_on))));
                if (ps.next != "") props.append ("<NextStyle type=\"object\">%s</NextStyle>".printf (XmlOut.esc (style_self ("ParagraphStyle", ps.next))));
                if (ps.chars.font != null) props.append ("<AppliedFont type=\"string\">%s</AppliedFont>".printf (XmlOut.esc (ps.chars.font)));
                props.append (leading_props (ps.para));
                if (ps.nested.size > 0) {
                    props.append ("<AllNestedStyles type=\"list\">");
                    string[] units = { "AnyCharacter", "AnyWord", "Sentence", "Tabs", "", "Digits", "Letters" };
                    foreach (var ns in ps.nested) {
                        props.append ("<ListItem type=\"record\"><AppliedCharacterStyle type=\"object\">%s</AppliedCharacterStyle>".printf (XmlOut.esc (style_self ("CharacterStyle", ns.cstyle))));
                        if (ns.unit == NestedUnit.CHARACTER) props.append ("<Delimiter type=\"string\">%s</Delimiter>".printf (XmlOut.esc (ns.character)));
                        else props.append ("<Delimiter type=\"enumeration\">%s</Delimiter>".printf (units[(int) ns.unit]));
                        props.append ("<Repetition type=\"long\">%d</Repetition><Inclusive type=\"boolean\">%s</Inclusive></ListItem>".printf (ns.count, ns.through ? "true" : "false"));
                    }
                    props.append ("</AllNestedStyles>");
                }
                if (ps.grep.size > 0) {
                    props.append ("<AllGREPStyles type=\"list\">");
                    foreach (var gs in ps.grep) props.append ("<ListItem type=\"record\"><AppliedCharacterStyle type=\"object\">%s</AppliedCharacterStyle><GrepExpression type=\"string\">%s</GrepExpression></ListItem>".printf (XmlOut.esc (style_self ("CharacterStyle", gs.cstyle)), XmlOut.esc (gs.pattern)));
                    props.append ("</AllGREPStyles>");
                }
                if (props.len > 0) sb.append ("<Properties>%s</Properties>".printf (props.str));
                sb.append ("</ParagraphStyle>");
            }
            sb.append ("</RootParagraphStyleGroup>");
            sb.append ("<RootCellStyleGroup Self=\"u7c\"><CellStyle Self=\"CellStyle/$ID/[None]\" Name=\"$ID/[None]\"/>");
            foreach (var cs in pub.cell_styles) {
                sb.append ("<CellStyle Self=\"%s\" Name=\"%s\"".printf (XmlOut.esc (style_self ("CellStyle", cs.name)), XmlOut.esc (cs.name)));
                if (cs.fill != "") sb.append (" FillColor=\"%s\"".printf (XmlOut.esc (color (cs.fill))));
                if (cs.valign >= 0) sb.append (" VerticalJustification=\"%s\"".printf (cs.valign == 1 ? "CenterAlign" : (cs.valign == 2 ? "BottomAlign" : "TopAlign")));
                if (cs.para_style != "") sb.append (" AppliedParagraphStyle=\"%s\"".printf (XmlOut.esc (style_self ("ParagraphStyle", cs.para_style))));
                if (cs.diagonal == 1) sb.append (" LeftToRightDiagonalLineStrokeWeight=\"1\"");
                sb.append (">");
                if (cs.based_on != "") sb.append ("<Properties><BasedOn type=\"object\">%s</BasedOn></Properties>".printf (XmlOut.esc (style_self ("CellStyle", cs.based_on))));
                sb.append ("</CellStyle>");
            }
            sb.append ("</RootCellStyleGroup><RootTableStyleGroup Self=\"u7d\"><TableStyle Self=\"TableStyle/$ID/[No Table Style]\" Name=\"$ID/[No Table Style]\"/>");
            foreach (var ts in pub.table_styles) {
                sb.append ("<TableStyle Self=\"%s\" Name=\"%s\"".printf (XmlOut.esc (style_self ("TableStyle", ts.name)), XmlOut.esc (ts.name)));
                if (ts.header_cell != "") sb.append (" HeaderRegionCellStyle=\"%s\"".printf (XmlOut.esc (style_self ("CellStyle", ts.header_cell))));
                if (ts.body_cell != "") sb.append (" BodyRegionCellStyle=\"%s\"".printf (XmlOut.esc (style_self ("CellStyle", ts.body_cell))));
                if (ts.first_col_cell != "") sb.append (" LeftColumnRegionCellStyle=\"%s\"".printf (XmlOut.esc (style_self ("CellStyle", ts.first_col_cell))));
                if (ts.alt_fill != "") sb.append (" EndRowFillColor=\"%s\"".printf (XmlOut.esc (color (ts.alt_fill))));
                if (ts.border_color != "") sb.append (" TopBorderStrokeColor=\"%s\"".printf (XmlOut.esc (color (ts.border_color))));
                if (ts.border_width >= 0) sb.append (" TopBorderStrokeWeight=\"%s\"".printf (n (ts.border_width)));
                sb.append (">");
                if (ts.based_on != "") sb.append ("<Properties><BasedOn type=\"object\">%s</BasedOn></Properties>".printf (XmlOut.esc (style_self ("TableStyle", ts.based_on))));
                sb.append ("</TableStyle>");
            }
            sb.append ("</RootTableStyleGroup><RootObjectStyleGroup Self=\"u7e\"><ObjectStyle Self=\"ObjectStyle/$ID/[None]\" Name=\"$ID/[None]\"/>");
            foreach (var os in pub.object_styles) {
                var proto = os.proto;
                sb.append ("<ObjectStyle Self=\"%s\" Name=\"%s\"".printf (XmlOut.esc (style_self ("ObjectStyle", os.name)), XmlOut.esc (os.name)));
                if (proto.fill.kind == FillKind.SOLID) sb.append (" FillColor=\"%s\"".printf (XmlOut.esc (color (proto.fill.color))));
                if (proto.stroke.visible ()) sb.append (" StrokeColor=\"%s\" StrokeWeight=\"%s\"".printf (XmlOut.esc (color (proto.stroke.color)), n (proto.stroke.width)));
                if (os.use_para && os.para_style != "") sb.append (" AppliedParagraphStyle=\"%s\"".printf (XmlOut.esc (style_self ("ParagraphStyle", os.para_style))));
                sb.append (">");
                if (os.based_on != "") sb.append ("<Properties><BasedOn type=\"object\">%s</BasedOn></Properties>".printf (XmlOut.esc (style_self ("ObjectStyle", os.based_on))));
                sb.append ("</ObjectStyle>");
            }
            sb.append ("</RootObjectStyleGroup>");
            sb.append ("</idPkg:Styles>");
            return sb.str;
        }

        private string page_xml (string self, string name, string master, int pi = -1) {
            var s = pub.settings;
            return "<Page Self=\"%s\" Name=\"%s\" AppliedMaster=\"%s\" GeometricBounds=\"0 0 %s %s\" ItemTransform=\"1 0 0 1 0 0\"><MarginPreference ColumnCount=\"%d\" ColumnGutter=\"%s\" Top=\"%s\" Bottom=\"%s\" Left=\"%s\" Right=\"%s\"/></Page>".printf (self, XmlOut.esc (name), master, n (pub.page_h (pi)), n (pub.page_w (pi)), s.columns, n (s.gutter), n (s.margin_top), n (s.margin_bottom), n (s.margin_inside), n (s.margin_outside));
        }

        public uint8[] write () throws Error {
            var zip = new ZipWriter ();
            zip.add_text ("mimetype", "application/vnd.adobe.indesign-idml-package", false);
            zip.add_text ("META-INF/container.xml", "<?xml version=\"1.0\" encoding=\"UTF-8\" standalone=\"yes\"?>\n<container version=\"1.0\" xmlns=\"urn:oasis:names:tc:opendocument:xmlns:container\"><rootfiles><rootfile full-path=\"designmap.xml\" media-type=\"text/xml\"/></rootfiles></container>");
            var dm = new StringBuilder ("<?xml version=\"1.0\" encoding=\"UTF-8\" standalone=\"yes\"?>\n<?aid style=\"50\" type=\"document\" readerVersion=\"6.0\" featureSet=\"257\" product=\"8.0(370)\" ?>\n");
            dm.append ("<Document xmlns:idPkg=\"%s\" DOMVersion=\"8.0\" Self=\"d\" StoryList=\"\" ZeroPoint=\"0 0\" ActiveLayer=\"u%x\" CMYKProfile=\"%s\" RGBProfile=\"sRGB IEC61966-2.1\">".printf (PKG, pub.layers.size > 0 ? pub.layers[0].id : 0, XmlOut.esc (ColorManager.for_settings (pub.settings).description ())));
            dm.append ("<idPkg:Graphic src=\"Resources/Graphic.xml\"/><idPkg:Styles src=\"Resources/Styles.xml\"/><idPkg:Preferences src=\"Resources/Preferences.xml\"/>");
            foreach (var l in pub.layers) dm.append ("<Layer Self=\"u%x\" Name=\"%s\" Visible=\"%s\" Locked=\"%s\" Printable=\"%s\"/>".printf (l.id, XmlOut.esc (l.name), l.visible ? "true" : "false", l.locked ? "true" : "false", l.printable ? "true" : "false"));
            var master_selfs = new Gee.HashMap<string, string> ();
            foreach (var m in pub.masters) {
                string mself = "um%s".printf (m.id.down ());
                master_selfs[m.id] = mself;
                var sb = new StringBuilder ("<?xml version=\"1.0\" encoding=\"UTF-8\" standalone=\"yes\"?>\n");
                sb.append ("<idPkg:MasterSpread xmlns:idPkg=\"%s\" DOMVersion=\"8.0\"><MasterSpread Self=\"%s\" Name=\"%s\" NamePrefix=\"%s\" BaseName=\"%s\" PageCount=\"1\" ItemTransform=\"1 0 0 1 0 0\">".printf (PKG, mself, XmlOut.esc (m.display_name ()), XmlOut.esc (m.id), XmlOut.esc (m.name)));
                sb.append (page_xml (mself + "p", m.id, "n"));
                foreach (var it in m.items) item (sb, it);
                sb.append ("</MasterSpread></idPkg:MasterSpread>");
                string file = "MasterSpreads/MasterSpread_%s.xml".printf (mself);
                zip.add_text (file, sb.str);
                dm.append ("<idPkg:MasterSpread src=\"%s\"/>".printf (file));
            }
            for (int pi = 0; pi < pub.pages.size; pi++) {
                var pg = pub.pages[pi];
                string sself = "us%x".printf (pg.id);
                var sb = new StringBuilder ("<?xml version=\"1.0\" encoding=\"UTF-8\" standalone=\"yes\"?>\n");
                sb.append ("<idPkg:Spread xmlns:idPkg=\"%s\" DOMVersion=\"8.0\"><Spread Self=\"%s\" PageCount=\"1\" BindingLocation=\"0\" ItemTransform=\"1 0 0 1 0 0\">".printf (PKG, sself));
                string master = pg.master != "" && !pg.hide_master && master_selfs.has_key (pg.master) ? master_selfs[pg.master] : "n";
                sb.append (page_xml ("up%x".printf (pg.id), pub.page_label (pi), master, pi));
                foreach (var it in pg.items) item (sb, it);
                sb.append ("</Spread></idPkg:Spread>");
                string file = "Spreads/Spread_%s.xml".printf (sself);
                zip.add_text (file, sb.str);
                dm.append ("<idPkg:Spread src=\"%s\"/>".printf (file));
            }
            var ids = new Gee.ArrayList<int> ();
            ids.add_all (stories_used);
            ids.sort ((a, b) => a - b);
            foreach (int sid in ids) {
                string file = "Stories/Story_u%x.xml".printf (sid);
                zip.add_text (file, story_xml (pub.story (sid)));
                dm.append ("<idPkg:Story src=\"%s\"/>".printf (file));
            }
            for (int i = 0; i < table_story_files.size; i++) {
                zip.add_text (table_story_files[i], table_story_xml[i]);
                dm.append ("<idPkg:Story src=\"%s\"/>".printf (table_story_files[i]));
            }
            dm.append ("</Document>");
            string styles = styles_xml ();
            var gr = new StringBuilder ("<?xml version=\"1.0\" encoding=\"UTF-8\" standalone=\"yes\"?>\n");
            gr.append ("<idPkg:Graphic xmlns:idPkg=\"%s\" DOMVersion=\"8.0\">".printf (PKG));
            gr.append ("<Color Self=\"Color/Black\" Model=\"Process\" Space=\"CMYK\" ColorValue=\"0 0 0 100\" Name=\"Black\"/><Color Self=\"Color/Paper\" Model=\"Process\" Space=\"CMYK\" ColorValue=\"0 0 0 0\" Name=\"Paper\"/><Color Self=\"Color/Registration\" Model=\"Registration\" Space=\"CMYK\" ColorValue=\"100 100 100 100\" Name=\"Registration\"/>");
            foreach (var sw in pub.swatches) if (sw.name != "Black" && sw.name != "Paper" && sw.name != "Registration") color (ColorRef.swatch (sw.name));
            foreach (string c in colors_xml) gr.append (c);
            gr.append ("<Swatch Self=\"Swatch/None\" Name=\"None\" ColorEditable=\"false\" ColorRemovable=\"false\" Visible=\"true\"/>");
            gr.append ("</idPkg:Graphic>");
            var s = pub.settings;
            var pr = new StringBuilder ("<?xml version=\"1.0\" encoding=\"UTF-8\" standalone=\"yes\"?>\n");
            pr.append ("<idPkg:Preferences xmlns:idPkg=\"%s\" DOMVersion=\"8.0\">".printf (PKG));
            pr.append ("<DocumentPreference PageHeight=\"%s\" PageWidth=\"%s\" PagesPerDocument=\"%d\" FacingPages=\"%s\" DocumentBleedTopOffset=\"%s\" DocumentBleedBottomOffset=\"%s\" DocumentBleedInsideOrLeftOffset=\"%s\" DocumentBleedOutsideOrRightOffset=\"%s\" DocumentBleedUniformSize=\"false\" SlugTopOffset=\"%s\" PageBinding=\"LeftToRight\"/>".printf (n (s.height), n (s.width), pub.pages.size, s.facing ? "true" : "false", n (s.bleed_top), n (s.bleed_bottom), n (s.bleed_inside), n (s.bleed_outside), n (s.slug)));
            pr.append ("<MarginPreference ColumnCount=\"%d\" ColumnGutter=\"%s\" Top=\"%s\" Bottom=\"%s\" Left=\"%s\" Right=\"%s\"/>".printf (s.columns, n (s.gutter), n (s.margin_top), n (s.margin_bottom), n (s.margin_inside), n (s.margin_outside)));
            pr.append ("<GridPreference BaselineStart=\"%s\" BaselineDivision=\"%s\"/>".printf (n (s.baseline_start), n (s.baseline_step)));
            pr.append ("</idPkg:Preferences>");
            zip.add_text ("designmap.xml", dm.str);
            zip.add_text ("Resources/Graphic.xml", gr.str);
            zip.add_text ("Resources/Styles.xml", styles);
            zip.add_text ("Resources/Preferences.xml", pr.str);
            var meta = new StringBuilder ("<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n<x:xmpmeta xmlns:x=\"adobe:ns:meta/\"><rdf:RDF xmlns:rdf=\"http://www.w3.org/1999/02/22-rdf-syntax-ns#\"><rdf:Description rdf:about=\"\" xmlns:dc=\"http://purl.org/dc/elements/1.1/\" xmlns:xmp=\"http://ns.adobe.com/xap/1.0/\"><xmp:CreatorTool>Singularity Publish</xmp:CreatorTool>");
            if (pub.meta.title != "") meta.append ("<dc:title><rdf:Alt><rdf:li xml:lang=\"x-default\">%s</rdf:li></rdf:Alt></dc:title>".printf (XmlOut.esc (pub.meta.title)));
            if (pub.meta.author != "") meta.append ("<dc:creator><rdf:Seq><rdf:li>%s</rdf:li></rdf:Seq></dc:creator>".printf (XmlOut.esc (pub.meta.author)));
            meta.append ("</rdf:Description></rdf:RDF></x:xmpmeta>");
            zip.add_text ("META-INF/metadata.xml", meta.str);
            return zip.finish ();
        }

        public static void export (Publication pub, string path) throws Error {
            FileUtils.set_data (path, new IdmlWriter (pub).write ());
        }
    }
}
