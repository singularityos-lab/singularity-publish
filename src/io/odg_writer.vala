namespace Singularity.Apps.Publish {

    public class OdgWriter {
        private Publication pub;
        private LayoutCache cache;
        private Renderer renderer;
        private Gee.ArrayList<string> auto_styles = new Gee.ArrayList<string> ();
        private Gee.HashMap<string, string> style_names = new Gee.HashMap<string, string> ();
        private Gee.ArrayList<string> pictures = new Gee.ArrayList<string> ();
        private Gee.ArrayList<Bytes> picture_data = new Gee.ArrayList<Bytes> ();
        private Gee.HashMap<string, string> picture_names = new Gee.HashMap<string, string> ();
        private int shape_counter = 0;

        public OdgWriter (Publication pub) {
            this.pub = pub;
            cache = new LayoutCache (pub);
            renderer = new Renderer (pub, cache);
            renderer.opts.print = true;
            renderer.opts.overset_marks = false;
            renderer.opts.placeholders = false;
        }

        private static string cm (double pt) {
            return "%scm".printf (XmlOut.num (Math.round (pt * 2.54 / 72 * 10000) / 10000));
        }

        private static string ptv (double pt) {
            return "%spt".printf (XmlOut.num (Math.round (pt * 100) / 100));
        }

        private string hex (string spec) {
            return pub.resolve_screen (spec).to_hex ();
        }

        private string auto_style (string family, string props) {
            string key = family + "|" + props;
            if (style_names.has_key (key)) return style_names[key];
            string prefix = family == "graphic" ? "gr" : (family == "paragraph" ? "P" : "T");
            string name = "%s%d".printf (prefix, style_names.size + 1);
            style_names[key] = name;
            auto_styles.add ("<style:style style:name=\"%s\" style:family=\"%s\">%s</style:style>".printf (name, family, props));
            return name;
        }

        private string graphic_style (Item it, bool text_box) {
            var sb = new StringBuilder ("<style:graphic-properties");
            var f = it.fill;
            if (f.kind == FillKind.SOLID && f.color != ColorRef.NONE) {
                var c = pub.resolve_screen (f.color);
                sb.append (" draw:fill=\"solid\" draw:fill-color=\"%s\"".printf (c.to_hex ()));
                if (c.a < 0.999) sb.append (" draw:opacity=\"%d%%\"".printf ((int) Math.round (c.a * 100)));
            } else if ((f.kind == FillKind.LINEAR || f.kind == FillKind.RADIAL) && f.stops.size >= 2) {
                sb.append (" draw:fill=\"solid\" draw:fill-color=\"%s\"".printf (hex (f.stops[0].color)));
            } else {
                sb.append (" draw:fill=\"none\"");
            }
            if (it.stroke.visible ()) {
                sb.append (" draw:stroke=\"%s\" svg:stroke-color=\"%s\" svg:stroke-width=\"%s\"".printf (it.stroke.dash == DashKind.SOLID ? "solid" : "dash", hex (it.stroke.color), cm (it.stroke.width)));
            } else {
                sb.append (" draw:stroke=\"none\"");
            }
            if (it.opacity < 0.999) sb.append (" draw:opacity=\"%d%%\"".printf ((int) Math.round (it.opacity * 100)));
            if (it.shadow.enabled) sb.append (" draw:shadow=\"visible\" draw:shadow-offset-x=\"%s\" draw:shadow-offset-y=\"%s\" draw:shadow-color=\"%s\" draw:shadow-opacity=\"%d%%\"".printf (cm (it.shadow.dx), cm (it.shadow.dy), hex (it.shadow.color), (int) Math.round (it.shadow.opacity * 100)));
            var t = it as TextFrame;
            if (text_box && t != null) {
                sb.append (" fo:padding-top=\"%s\" fo:padding-bottom=\"%s\" fo:padding-left=\"%s\" fo:padding-right=\"%s\"".printf (cm (t.inset_top), cm (t.inset_bottom), cm (t.inset_left), cm (t.inset_right)));
                sb.append (" draw:textarea-vertical-align=\"%s\" draw:auto-grow-height=\"false\" fo:min-height=\"0cm\"".printf (t.valign == 1 ? "middle" : (t.valign == 2 ? "bottom" : "top")));
                if (t.columns > 1) sb.append ("><style:columns fo:column-count=\"%d\" fo:column-gap=\"%s\"/></style:graphic-properties>".printf (t.columns, cm (t.gutter)));
                else sb.append ("/>");
            } else {
                sb.append ("/>");
            }
            return auto_style ("graphic", sb.str);
        }

        private string para_style (ParaFormat pf, string parent) {
            var sb = new StringBuilder ("<style:paragraph-properties");
            string[] aligns = { "start", "center", "end", "justify", "justify" };
            if (pf.align >= 0) sb.append (" fo:text-align=\"%s\"".printf (aligns[pf.align.clamp (0, 4)]));
            if (!pf.left_indent.is_nan ()) sb.append (" fo:margin-left=\"%s\"".printf (cm (pf.left_indent)));
            if (!pf.right_indent.is_nan ()) sb.append (" fo:margin-right=\"%s\"".printf (cm (pf.right_indent)));
            if (!pf.first_indent.is_nan ()) sb.append (" fo:text-indent=\"%s\"".printf (cm (pf.first_indent)));
            if (!pf.space_before.is_nan ()) sb.append (" fo:margin-top=\"%s\"".printf (cm (pf.space_before)));
            if (!pf.space_after.is_nan ()) sb.append (" fo:margin-bottom=\"%s\"".printf (cm (pf.space_after)));
            if (!pf.leading.is_nan () && pf.leading > 0.01) sb.append (" fo:line-height=\"%s\"".printf (cm (pf.leading)));
            sb.append ("/>");
            string props = sb.str;
            if (parent != "") props = "PARENT:" + parent + props;
            string key = "paragraph|" + props;
            if (style_names.has_key (key)) return style_names[key];
            string name = "P%d".printf (style_names.size + 1);
            style_names[key] = name;
            auto_styles.add ("<style:style style:name=\"%s\" style:family=\"paragraph\"%s>%s</style:style>".printf (name, parent != "" ? " style:parent-style-name=\"%s\"".printf (XmlOut.esc (odf_name (parent))) : "", sb.str));
            return name;
        }

        public static string odf_name (string name) {
            var sb = new StringBuilder ();
            unichar c;
            int i = 0;
            while (name.get_next_char (ref i, out c)) {
                if (c.isalnum ()) sb.append_unichar (c);
                else if (c == ' ') sb.append ("_20_");
                else sb.append_printf ("_%x_", (uint) c);
            }
            return sb.str;
        }

        private static string text_props (CharFormat f) {
            var sb = new StringBuilder ("<style:text-properties");
            if (f.font != null) sb.append (" fo:font-family=\"'%s'\"".printf (XmlOut.esc (f.font)));
            if (!f.size.is_nan ()) sb.append (" fo:font-size=\"%s\"".printf (ptv (f.size)));
            if (f.bold >= 0) sb.append (" fo:font-weight=\"%s\"".printf (f.bold == 1 ? "bold" : "normal"));
            if (f.italic >= 0) sb.append (" fo:font-style=\"%s\"".printf (f.italic == 1 ? "italic" : "normal"));
            if (f.underline == 1) sb.append (" style:text-underline-style=\"solid\" style:text-underline-width=\"auto\" style:text-underline-color=\"font-color\"");
            if (f.strike == 1) sb.append (" style:text-line-through-style=\"solid\"");
            if (f.caps == 1) sb.append (" fo:text-transform=\"uppercase\"");
            if (f.caps == 2) sb.append (" fo:font-variant=\"small-caps\"");
            if (f.position == 1) sb.append (" style:text-position=\"super 58%\"");
            if (f.position == 2) sb.append (" style:text-position=\"sub 58%\"");
            if (f.text_shadow == 1) sb.append (" fo:text-shadow=\"1pt 1pt\"");
            if (f.outline_color != null && f.outline_color != "" && f.outline_width > 0) sb.append (" style:text-outline=\"true\"");
            if (f.emboss == 1) sb.append (" style:font-relief=\"embossed\"");
            if (f.emboss == 2) sb.append (" style:font-relief=\"engraved\"");
            if (f.lang != null && f.lang.length >= 2) sb.append (" fo:language=\"%s\"".printf (f.lang.substring (0, 2)));
            return sb.str;
        }

        private string span_style (CharFormat f) {
            var sb = new StringBuilder (text_props (f));
            if (f.color != null) sb.append (" fo:color=\"%s\"".printf (hex (f.color)));
            sb.append ("/>");
            return auto_style ("text", sb.str);
        }

        private void story (XmlOut x, Story st, int page_index) {
            var fc = new FieldContext (pub);
            fc.page_index = page_index;
            foreach (var p in st.paras) {
                x.start ("text:p").a ("text:style-name", para_style (p.fmt, p.style));
                foreach (var r in p.runs) {
                    string text = r.field != "" ? fc.resolve (r.field) : r.text;
                    if (text == "") continue;
                    bool link = r.fmt.link != null && r.fmt.link != "";
                    if (link) x.start ("text:a").a ("xlink:type", "simple").a ("xlink:href", HtmlExport.link_href (r.fmt.link));
                    var f = new CharFormat ();
                    if (r.cstyle != "") pub.styles.resolve_character (r.cstyle, f);
                    f.apply (r.fmt);
                    x.start ("text:span").a ("text:style-name", span_style (f));
                    string[] lines = text.replace ("­", "").replace ("​", "").split (" ");
                    for (int i = 0; i < lines.length; i++) {
                        if (i > 0) x.empty ("text:line-break");
                        string[] tabs = lines[i].split ("\t");
                        for (int k = 0; k < tabs.length; k++) {
                            if (k > 0) x.empty ("text:tab");
                            string seg = tabs[k];
                            int j = 0;
                            var buf = new StringBuilder ();
                            while (j < seg.length) {
                                if (seg[j] == ' ' && j + 1 < seg.length && seg[j + 1] == ' ') {
                                    int n = 0;
                                    while (j < seg.length && seg[j] == ' ') {
                                        n++;
                                        j++;
                                    }
                                    x.text (buf.str);
                                    buf.truncate ();
                                    x.text (" ");
                                    if (n > 1) x.start ("text:s").ai ("text:c", n - 1).end ();
                                    continue;
                                }
                                buf.append_c (seg[j]);
                                j++;
                            }
                            x.text (buf.str);
                        }
                    }
                    x.end ();
                    if (link) x.end ();
                }
                x.end ();
            }
        }

        private void place (XmlOut x, Item it) {
            if (it.rotation == 0) {
                x.a ("svg:x", cm (it.x)).a ("svg:y", cm (it.y)).a ("svg:width", cm (it.w)).a ("svg:height", cm (double.max (0.01, it.h)));
                return;
            }
            var tl = it.to_page (0, 0);
            double rad = -it.rotation * Math.PI / 180;
            x.a ("svg:width", cm (it.w)).a ("svg:height", cm (double.max (0.01, it.h)));
            x.a ("draw:transform", "rotate (%s) translate (%s %s)".printf (XmlOut.num (Math.round (rad * 1000000) / 1000000), cm (tl.x), cm (tl.y)));
        }

        private string add_picture (uint8[] data, string ext) {
            string key = Checksum.compute_for_data (ChecksumType.SHA1, data);
            if (picture_names.has_key (key)) return picture_names[key];
            string name = "Pictures/%s.%s".printf (key.substring (0, 16), ext);
            pictures.add (name);
            picture_data.add (new Bytes (data));
            picture_names[key] = name;
            return name;
        }

        private void title_desc (XmlOut x, Item it) {
            if (it.name != "") x.element ("svg:title", it.name);
            if (it.alt_text != "" && !it.alt_decorative) x.element ("svg:desc", it.alt_text);
        }

        private void snapshot (XmlOut x, Item it, bool master, int page_index) {
            double pad = 2;
            if (it.shadow.enabled) pad = double.max (pad, it.shadow.blur * 2 + 6);
            if (it.effects.glow) pad = double.max (pad, it.effects.glow_size * 2 + 4);
            var bb = it.bounds ();
            var where = Rect (bb.x - pad, bb.y - pad, bb.w + 2 * pad, bb.h + 2 * pad);
            double sc = 3;
            var surf = new Cairo.ImageSurface (Cairo.Format.ARGB32, int.max (1, (int) Math.ceil (where.w * sc)), int.max (1, (int) Math.ceil (where.h * sc)));
            var cr = new Cairo.Context (surf);
            cr.scale (sc, sc);
            cr.translate (-where.x, -where.y);
            renderer.draw_item (cr, it, master, page_index);
            string href = add_picture (XpsExport.surface_png (surf), "png");
            x.start ("draw:frame").a ("draw:name", "Object %d".printf (++shape_counter)).a ("draw:style-name", auto_style ("graphic", "<style:graphic-properties draw:fill=\"none\" draw:stroke=\"none\"/>"));
            x.a ("svg:x", cm (where.x)).a ("svg:y", cm (where.y)).a ("svg:width", cm (where.w)).a ("svg:height", cm (where.h));
            x.start ("draw:image").a ("xlink:href", href).a ("xlink:type", "simple").a ("xlink:show", "embed").a ("xlink:actuate", "onLoad").end ();
            title_desc (x, it);
            var wa = it as WordArtItem;
            if (wa != null && it.alt_text == "") x.element ("svg:desc", wa.text);
            x.end ();
        }

        private void item (XmlOut x, Item it, bool master, int page_index) {
            if (it.hidden || it.nonprinting) return;
            var layer = pub.layer (it.layer);
            if (layer != null && (!layer.visible || !layer.printable)) return;
            bool linked = it.link != "";
            if (linked) x.start ("draw:a").a ("xlink:type", "simple").a ("xlink:href", HtmlExport.link_href (it.link));
            item_body (x, it, master, page_index);
            if (linked) x.end ();
        }

        private void item_body (XmlOut x, Item it, bool master, int page_index) {
            var g = it as GroupItem;
            if (g != null && !g.effects.any () && !g.shadow.enabled && g.rotation == 0) {
                x.start ("draw:g");
                foreach (var c in renderer.ordered (g.children)) item (x, c, master, page_index);
                x.end ();
                return;
            }
            bool plain = !it.effects.any () && !it.border_art.visible () && it.fill.kind != FillKind.PATTERN && it.fill.kind != FillKind.TEXTURE && it.fill.kind != FillKind.PICTURE;
            var t = it as TextFrame;
            if (t != null && plain && !t.vertical) {
                var res = master ? cache.master_story (t.story, page_index) : cache.story (t.story);
                var fr = res.frame_result (t.id);
                x.start ("draw:frame").a ("draw:name", t.name != "" ? t.name : "Text %d".printf (++shape_counter)).a ("draw:style-name", graphic_style (t, true));
                place (x, t);
                x.start ("draw:text-box");
                if (fr != null && !fr.empty) story (x, pub.story (t.story).copy_range (fr.first, fr.last), page_index);
                else x.empty ("text:p");
                x.end ();
                title_desc (x, t);
                x.end ();
                return;
            }
            var im = it as ImageFrame;
            if (im != null && plain && !im.adjusted () && im.clip_shape == "" && !im.shape_ellipse && im.merge_field == "" && im.fit != FitMode.MANUAL) {
                var data = ImageStore.get_default ().bytes_for (pub, im);
                var inf = ImageStore.get_default ().info (pub, im);
                if (data != null && inf != null) {
                    string ext = ImageStore.sniff (data);
                    if (ext == "") ext = "png";
                    var pl = ImageStore.place (im, inf);
                    double iw = inf.width * pl.sx, ih = inf.height * pl.sy;
                    double cl = double.max (0, -pl.ox), ctop = double.max (0, -pl.oy);
                    double cr_ = double.max (0, pl.ox + iw - im.w), cb = double.max (0, pl.oy + ih - im.h);
                    var props = new StringBuilder ("<style:graphic-properties draw:fill=\"none\"");
                    if (im.stroke.visible ()) props.append (" draw:stroke=\"solid\" svg:stroke-color=\"%s\" svg:stroke-width=\"%s\"".printf (hex (im.stroke.color), cm (im.stroke.width)));
                    else props.append (" draw:stroke=\"none\"");
                    if (cl + ctop + cr_ + cb > 0.01) props.append (" fo:clip=\"rect(%s, %s, %s, %s)\"".printf (cm (ctop / pl.sy * 72 / inf.dpi), cm (cr_ / pl.sx * 72 / inf.dpi), cm (cb / pl.sy * 72 / inf.dpi), cm (cl / pl.sx * 72 / inf.dpi)));
                    props.append ("/>");
                    x.start ("draw:frame").a ("draw:name", im.name != "" ? im.name : "Picture %d".printf (++shape_counter)).a ("draw:style-name", auto_style ("graphic", props.str));
                    place (x, im);
                    x.start ("draw:image").a ("xlink:href", add_picture (data, ext)).a ("xlink:type", "simple").a ("xlink:show", "embed").a ("xlink:actuate", "onLoad").end ();
                    title_desc (x, im);
                    x.end ();
                    return;
                }
            }
            var s = it as ShapeItem;
            if (s != null && plain && !(s is WordArtItem) && s.fill.kind != FillKind.LINEAR && s.fill.kind != FillKind.RADIAL) {
                string style = graphic_style (s, false);
                switch (s.shape) {
                    case ShapeKind.RECT:
                        x.start ("draw:rect").a ("draw:style-name", style);
                        if (s.corner == CornerKind.ROUNDED && s.corner_radius > 0) x.a ("draw:corner-radius", cm (s.corner_radius));
                        place (x, s);
                        title_desc (x, s);
                        x.end ();
                        return;
                    case ShapeKind.ELLIPSE:
                        x.start ("draw:ellipse").a ("draw:style-name", style);
                        place (x, s);
                        title_desc (x, s);
                        x.end ();
                        return;
                    case ShapeKind.LINE:
                        var pts = s.local_points ();
                        var a = s.to_page (pts[0].x, pts[0].y);
                        var b = s.to_page (pts[1].x, pts[1].y);
                        x.start ("draw:line").a ("draw:style-name", style).a ("svg:x1", cm (a.x)).a ("svg:y1", cm (a.y)).a ("svg:x2", cm (b.x)).a ("svg:y2", cm (b.y));
                        title_desc (x, s);
                        x.end ();
                        return;
                    default:
                        var lp = s.local_points ();
                        double vw = double.max (1, s.w), vh = double.max (1, s.h);
                        var sb = new StringBuilder ();
                        foreach (var p in lp) {
                            if (sb.len > 0) sb.append (" ");
                            sb.append ("%d,%d".printf ((int) Math.round (p.x / vw * 10000), (int) Math.round (p.y / vh * 10000)));
                        }
                        bool open_path = s.shape == ShapeKind.PATH && !s.closed;
                        x.start (open_path ? "draw:polyline" : "draw:polygon").a ("draw:style-name", style);
                        place (x, s);
                        x.a ("svg:viewBox", "0 0 10000 10000").a ("draw:points", sb.str);
                        title_desc (x, s);
                        x.end ();
                        return;
                }
            }
            snapshot (x, it, master, page_index);
        }

        public string content_xml () {
            var body = new XmlOut (false);
            body.start ("office:body").start ("office:drawing");
            for (int pi = 0; pi < pub.pages.size; pi++) {
                body.start ("draw:page").a ("draw:name", _("Page %s").printf (pub.page_label (pi))).a ("draw:master-page-name", "Default");
                var all = new Gee.ArrayList<Item> ();
                var masters = new Gee.HashSet<Item> ();
                foreach (var it in pub.master_items_for (pi)) {
                    all.add (it);
                    masters.add (it);
                }
                all.add_all (pub.pages[pi].items);
                foreach (var it in renderer.ordered (all)) item (body, it, masters.contains (it), pi);
                body.end ();
            }
            body.end ().end ();
            string body_xml = body.finish ();
            var sb = new StringBuilder ("<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n");
            sb.append ("<office:document-content xmlns:office=\"urn:oasis:names:tc:opendocument:xmlns:office:1.0\" xmlns:style=\"urn:oasis:names:tc:opendocument:xmlns:style:1.0\" xmlns:text=\"urn:oasis:names:tc:opendocument:xmlns:text:1.0\" xmlns:draw=\"urn:oasis:names:tc:opendocument:xmlns:drawing:1.0\" xmlns:fo=\"urn:oasis:names:tc:opendocument:xmlns:xsl-fo-compatible:1.0\" xmlns:xlink=\"http://www.w3.org/1999/xlink\" xmlns:svg=\"urn:oasis:names:tc:opendocument:xmlns:svg-compatible:1.0\" xmlns:table=\"urn:oasis:names:tc:opendocument:xmlns:table:1.0\" office:version=\"1.3\">");
            sb.append ("<office:automatic-styles>");
            foreach (string st in auto_styles) sb.append (st);
            sb.append ("</office:automatic-styles>");
            sb.append (body_xml);
            sb.append ("</office:document-content>");
            return sb.str;
        }

        public string styles_xml () {
            var s = pub.settings;
            var x = new StringBuilder ("<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n");
            x.append ("<office:document-styles xmlns:office=\"urn:oasis:names:tc:opendocument:xmlns:office:1.0\" xmlns:style=\"urn:oasis:names:tc:opendocument:xmlns:style:1.0\" xmlns:text=\"urn:oasis:names:tc:opendocument:xmlns:text:1.0\" xmlns:draw=\"urn:oasis:names:tc:opendocument:xmlns:drawing:1.0\" xmlns:fo=\"urn:oasis:names:tc:opendocument:xmlns:xsl-fo-compatible:1.0\" xmlns:svg=\"urn:oasis:names:tc:opendocument:xmlns:svg-compatible:1.0\" office:version=\"1.3\">");
            x.append ("<office:styles>");
            x.append ("<style:default-style style:family=\"graphic\"><style:graphic-properties draw:fill=\"none\" draw:stroke=\"none\"/><style:text-properties fo:font-size=\"11pt\"/></style:default-style>");
            foreach (var ps in pub.styles.paragraph) {
                x.append ("<style:style style:name=\"%s\" style:display-name=\"%s\" style:family=\"paragraph\"".printf (XmlOut.esc (odf_name (ps.name)), XmlOut.esc (ps.name)));
                if (ps.based_on != "") x.append (" style:parent-style-name=\"%s\"".printf (XmlOut.esc (odf_name (ps.based_on))));
                x.append (">");
                var pp = new StringBuilder ("<style:paragraph-properties");
                var pf = ps.para;
                string[] aligns = { "start", "center", "end", "justify", "justify" };
                if (pf.align >= 0) pp.append (" fo:text-align=\"%s\"".printf (aligns[pf.align.clamp (0, 4)]));
                if (!pf.left_indent.is_nan ()) pp.append (" fo:margin-left=\"%s\"".printf (cm (pf.left_indent)));
                if (!pf.first_indent.is_nan ()) pp.append (" fo:text-indent=\"%s\"".printf (cm (pf.first_indent)));
                if (!pf.space_before.is_nan ()) pp.append (" fo:margin-top=\"%s\"".printf (cm (pf.space_before)));
                if (!pf.space_after.is_nan ()) pp.append (" fo:margin-bottom=\"%s\"".printf (cm (pf.space_after)));
                if (!pf.leading.is_nan () && pf.leading > 0.01) pp.append (" fo:line-height=\"%s\"".printf (cm (pf.leading)));
                pp.append ("/>");
                x.append (pp.str);
                var tp = new StringBuilder (text_props (ps.chars));
                if (ps.chars.color != null) tp.append (" fo:color=\"%s\"".printf (hex (ps.chars.color)));
                tp.append ("/>");
                x.append (tp.str);
                x.append ("</style:style>");
            }
            x.append ("</office:styles>");
            x.append ("<office:automatic-styles><style:page-layout style:name=\"PM1\"><style:page-layout-properties fo:margin-top=\"0cm\" fo:margin-bottom=\"0cm\" fo:margin-left=\"0cm\" fo:margin-right=\"0cm\" fo:page-width=\"%s\" fo:page-height=\"%s\" style:print-orientation=\"%s\"/></style:page-layout></office:automatic-styles>".printf (cm (s.width), cm (s.height), s.landscape () ? "landscape" : "portrait"));
            x.append ("<office:master-styles><style:master-page style:name=\"Default\" style:page-layout-name=\"PM1\"/></office:master-styles>");
            x.append ("</office:document-styles>");
            return x.str;
        }

        public uint8[] write () throws Error {
            string content = content_xml ();
            string styles = styles_xml ();
            var zip = new ZipWriter ();
            zip.add_text ("mimetype", "application/vnd.oasis.opendocument.graphics", false);
            var man = new StringBuilder ("<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n<manifest:manifest xmlns:manifest=\"urn:oasis:names:tc:opendocument:xmlns:manifest:1.0\" manifest:version=\"1.3\"><manifest:file-entry manifest:full-path=\"/\" manifest:version=\"1.3\" manifest:media-type=\"application/vnd.oasis.opendocument.graphics\"/><manifest:file-entry manifest:full-path=\"content.xml\" manifest:media-type=\"text/xml\"/><manifest:file-entry manifest:full-path=\"styles.xml\" manifest:media-type=\"text/xml\"/><manifest:file-entry manifest:full-path=\"meta.xml\" manifest:media-type=\"text/xml\"/>");
            foreach (string p in pictures) {
                string mime = p.has_suffix (".png") ? "image/png" : (p.has_suffix (".jpg") ? "image/jpeg" : "image/" + p.substring (p.last_index_of (".") + 1));
                man.append ("<manifest:file-entry manifest:full-path=\"%s\" manifest:media-type=\"%s\"/>".printf (p, mime));
            }
            man.append ("</manifest:manifest>");
            zip.add_text ("content.xml", content);
            zip.add_text ("styles.xml", styles);
            var meta = new XmlOut ();
            meta.start ("office:document-meta").a ("xmlns:office", "urn:oasis:names:tc:opendocument:xmlns:office:1.0").a ("xmlns:meta", "urn:oasis:names:tc:opendocument:xmlns:meta:1.0").a ("xmlns:dc", "http://purl.org/dc/elements/1.1/").a ("office:version", "1.3").start ("office:meta");
            meta.element ("meta:generator", "Singularity Publish");
            if (pub.meta.title != "") meta.element ("dc:title", pub.meta.title);
            if (pub.meta.author != "") meta.element ("dc:creator", pub.meta.author);
            if (pub.meta.subject != "") meta.element ("dc:subject", pub.meta.subject);
            meta.element ("meta:creation-date", new DateTime.now_utc ().format ("%Y-%m-%dT%H:%M:%S"));
            meta.end ().end ();
            zip.add_text ("meta.xml", meta.finish ());
            for (int i = 0; i < pictures.size; i++) zip.add (pictures[i], picture_data[i].get_data (), false);
            zip.add_text ("META-INF/manifest.xml", man.str);
            return zip.finish ();
        }

        public static void export (Publication pub, string path) throws Error {
            FileUtils.set_data (path, new OdgWriter (pub).write ());
        }
    }
}
