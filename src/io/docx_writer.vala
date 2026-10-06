namespace Singularity.Apps.Publish {

    public class DocxWriter {
        public const string W = "http://schemas.openxmlformats.org/wordprocessingml/2006/main";
        private Publication pub;
        private LayoutCache cache;
        private Renderer renderer;
        private Gee.ArrayList<string> rels = new Gee.ArrayList<string> ();
        private Gee.HashMap<string, string> media_rel = new Gee.HashMap<string, string> ();
        private Gee.HashMap<string, string> link_rel = new Gee.HashMap<string, string> ();
        private Gee.ArrayList<string> media_names = new Gee.ArrayList<string> ();
        private Gee.ArrayList<Bytes> media_data = new Gee.ArrayList<Bytes> ();
        private Gee.HashMap<string, string> style_ids = new Gee.HashMap<string, string> ();
        private int rel_counter = 10;
        private int shape_id = 1;

        public DocxWriter (Publication pub) {
            this.pub = pub;
            cache = new LayoutCache (pub);
            renderer = new Renderer (pub, cache);
            renderer.opts.print = true;
            renderer.opts.overset_marks = false;
            renderer.opts.placeholders = false;
        }

        private static long emu (double pt) {
            return (long) Math.round (pt * 12700);
        }

        private static int twips (double pt) {
            return (int) Math.round (pt * 20);
        }

        private string hex (string spec) {
            return pub.resolve_screen (spec).to_hex ().substring (1).up ();
        }

        private string style_id (string name) {
            if (style_ids.has_key (name)) return style_ids[name];
            var sb = new StringBuilder ();
            unichar c;
            int i = 0;
            while (name.get_next_char (ref i, out c)) if (c.isalnum ()) sb.append_unichar (c);
            string id = sb.str != "" ? sb.str : "Style";
            string base_id = id;
            int k = 2;
            while (style_ids.values.contains (id)) id = "%s%d".printf (base_id, k++);
            style_ids[name] = id;
            return id;
        }

        private string add_media (uint8[] data, string ext) {
            string key = Checksum.compute_for_data (ChecksumType.SHA1, data);
            if (media_rel.has_key (key)) return media_rel[key];
            string name = "image%d.%s".printf (media_names.size + 1, ext);
            media_names.add (name);
            media_data.add (new Bytes (data));
            string id = "rId%d".printf (rel_counter++);
            rels.add ("<Relationship Id=\"%s\" Type=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships/image\" Target=\"media/%s\"/>".printf (id, name));
            media_rel[key] = id;
            return id;
        }

        private string add_link (string url) {
            if (link_rel.has_key (url)) return link_rel[url];
            string id = "rId%d".printf (rel_counter++);
            rels.add ("<Relationship Id=\"%s\" Type=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships/hyperlink\" Target=\"%s\" TargetMode=\"External\"/>".printf (id, XmlOut.esc (url)));
            link_rel[url] = id;
            return id;
        }

        private void rpr (XmlOut x, CharFormat f, bool full) {
            x.start ("w:rPr");
            rpr_inner (x, f, full);
            x.end ();
        }

        private void rpr_inner (XmlOut x, CharFormat f, bool full) {
            if (f.font != null) x.start ("w:rFonts").a ("w:ascii", f.font).a ("w:hAnsi", f.font).a ("w:cs", f.font).end ();
            if (f.bold >= 0 && (full || f.bold == 1)) x.start ("w:b").a ("w:val", f.bold == 1 ? "1" : "0").end ();
            if (f.italic >= 0 && (full || f.italic == 1)) x.start ("w:i").a ("w:val", f.italic == 1 ? "1" : "0").end ();
            if (f.caps == 1) x.empty ("w:caps");
            if (f.caps == 2) x.empty ("w:smallCaps");
            if (f.strike == 1) x.empty ("w:strike");
            if (f.outline_color != null && f.outline_color != "" && f.outline_width > 0) x.empty ("w:outline");
            if (f.text_shadow == 1) x.empty ("w:shadow");
            if (f.emboss == 1) x.empty ("w:emboss");
            if (f.emboss == 2) x.empty ("w:imprint");
            if (f.color != null) x.start ("w:color").a ("w:val", hex (f.color)).end ();
            if (!f.tracking.is_nan () && Math.fabs (f.tracking) > 0.01 && !f.size.is_nan ()) x.start ("w:spacing").ai ("w:val", twips (f.size * f.tracking / 1000)).end ();
            if (!f.size.is_nan ()) {
                x.start ("w:sz").ai ("w:val", (int) Math.round (f.size * 2)).end ();
                x.start ("w:szCs").ai ("w:val", (int) Math.round (f.size * 2)).end ();
            }
            if (f.underline == 1) x.start ("w:u").a ("w:val", "single").end ();
            if (f.position == 1) x.start ("w:vertAlign").a ("w:val", "superscript").end ();
            if (f.position == 2) x.start ("w:vertAlign").a ("w:val", "subscript").end ();
            if (f.lang != null && f.lang != "") x.start ("w:lang").a ("w:val", f.lang).end ();
        }

        private void ppr_body (XmlOut x, ParaFormat pf) {
            if (pf.keep_next == 1) x.empty ("w:keepNext");
            if (pf.keep_lines == 1) x.empty ("w:keepLines");
            var tabs = TabStop.parse (pf.tabs);
            if (tabs.size > 0) {
                x.start ("w:tabs");
                foreach (var t in tabs) {
                    string v = t.kind == TabKind.RIGHT ? "right" : (t.kind == TabKind.CENTER ? "center" : (t.kind == TabKind.DECIMAL ? "decimal" : "left"));
                    x.start ("w:tab").a ("w:val", v).ai ("w:pos", twips (t.pos));
                    if (t.leader == ".") x.a ("w:leader", "dot");
                    else if (t.leader == "-") x.a ("w:leader", "hyphen");
                    else if (t.leader == "_") x.a ("w:leader", "underscore");
                    x.end ();
                }
                x.end ();
            }
            if (!pf.space_before.is_nan () || !pf.space_after.is_nan () || (!pf.leading.is_nan () && pf.leading > 0.01)) {
                x.start ("w:spacing");
                if (!pf.space_before.is_nan ()) x.ai ("w:before", twips (pf.space_before));
                if (!pf.space_after.is_nan ()) x.ai ("w:after", twips (pf.space_after));
                if (!pf.leading.is_nan () && pf.leading > 0.01) x.ai ("w:line", twips (pf.leading)).a ("w:lineRule", "exact");
                x.end ();
            }
            if (!pf.left_indent.is_nan () || !pf.right_indent.is_nan () || !pf.first_indent.is_nan ()) {
                x.start ("w:ind");
                if (!pf.left_indent.is_nan ()) x.ai ("w:left", twips (pf.left_indent));
                if (!pf.right_indent.is_nan ()) x.ai ("w:right", twips (pf.right_indent));
                if (!pf.first_indent.is_nan ()) {
                    if (pf.first_indent < 0) x.ai ("w:hanging", twips (-pf.first_indent));
                    else x.ai ("w:firstLine", twips (pf.first_indent));
                }
                x.end ();
            }
            if (pf.align >= 0) {
                string[] jc = { "left", "center", "right", "both", "distribute" };
                x.start ("w:jc").a ("w:val", jc[pf.align.clamp (0, 4)]).end ();
            }
        }

        public string styles_xml () {
            var x = new XmlOut ();
            x.start ("w:styles").a ("xmlns:w", W);
            x.start ("w:docDefaults").start ("w:rPrDefault");
            rpr (x, CharFormat.defaults (), false);
            x.end ().end ();
            foreach (var ps in pub.styles.paragraph) {
                x.start ("w:style").a ("w:type", "paragraph").a ("w:styleId", style_id (ps.name));
                if (ps.name == StyleSheet.BASIC) x.a ("w:default", "1");
                x.start ("w:name").a ("w:val", ps.name).end ();
                if (ps.based_on != "") x.start ("w:basedOn").a ("w:val", style_id (ps.based_on)).end ();
                if (ps.next != "") x.start ("w:next").a ("w:val", style_id (ps.next)).end ();
                x.empty ("w:qFormat");
                x.start ("w:pPr");
                ppr_body (x, ps.para);
                x.end ();
                rpr (x, ps.chars, true);
                x.end ();
            }
            foreach (var cs in pub.styles.character) {
                x.start ("w:style").a ("w:type", "character").a ("w:styleId", style_id ("char " + cs.name));
                x.start ("w:name").a ("w:val", cs.name).end ();
                if (cs.based_on != "") x.start ("w:basedOn").a ("w:val", style_id ("char " + cs.based_on)).end ();
                rpr (x, cs.chars, true);
                x.end ();
            }
            x.end ();
            return x.finish ();
        }

        private void runs_of (XmlOut x, Paragraph p, int page_index) {
            var fc = new FieldContext (pub);
            fc.page_index = page_index;
            foreach (var r in p.runs) {
                string text = r.field != "" ? fc.resolve (r.field) : r.text;
                if (text == "") continue;
                string? link = r.fmt.link;
                bool open_link = link != null && link != "";
                if (open_link) {
                    x.start ("w:hyperlink");
                    if (link.has_prefix ("bookmark:")) x.a ("w:anchor", Renderer.dest_name (link.substring (9)));
                    else if (link.has_prefix ("page:")) x.a ("w:anchor", "page-%d".printf (int.parse (link.substring (5)) + 1));
                    else x.a ("r:id", add_link (HtmlExport.link_href (link)));
                }
                x.start ("w:r");
                var own = r.fmt.clone ();
                own.link = null;
                if (r.cstyle != "" || !own.is_empty ()) {
                    x.start ("w:rPr");
                    if (r.cstyle != "") x.start ("w:rStyle").a ("w:val", style_id ("char " + r.cstyle)).end ();
                    rpr_inner (x, own, false);
                    x.end ();
                }
                string[] parts = text.replace ("­", "").split (" ");
                for (int i = 0; i < parts.length; i++) {
                    if (i > 0) x.empty ("w:br");
                    string[] tabs = parts[i].split ("\t");
                    for (int k = 0; k < tabs.length; k++) {
                        if (k > 0) x.empty ("w:tab");
                        if (tabs[k] != "") x.start ("w:t").a ("xml:space", "preserve").text (tabs[k].replace ("​", "")).end ();
                    }
                }
                x.end ();
                if (open_link) x.end ();
            }
        }

        private void paragraph (XmlOut x, Paragraph p, int page_index) {
            x.start ("w:p");
            x.start ("w:pPr");
            x.start ("w:pStyle").a ("w:val", style_id (p.style)).end ();
            ppr_body (x, p.fmt);
            x.end ();
            runs_of (x, p, page_index);
            x.end ();
        }

        private void story_body (XmlOut x, Story st, int page_index) {
            if (st.paras.size == 0) {
                x.empty ("w:p");
                return;
            }
            foreach (var p in st.paras) paragraph (x, p, page_index);
        }

        private void anchor_open (XmlOut x, Item it, Rect r, string name, string descr) {
            x.start ("w:r").start ("w:drawing");
            x.start ("wp:anchor").ai ("distT", 0).ai ("distB", 0).ai ("distL", 0).ai ("distR", 0).ai ("simplePos", 0).ai ("relativeHeight", 251658240 + shape_id).ai ("behindDoc", it.wrap == WrapMode.BEHIND ? 1 : 0).ai ("locked", it.locked ? 1 : 0).ai ("layoutInCell", 1).ai ("allowOverlap", 1);
            x.start ("wp:simplePos").ai ("x", 0).ai ("y", 0).end ();
            x.start ("wp:positionH").a ("relativeFrom", "page").start ("wp:posOffset").text (emu (r.x).to_string ()).end ().end ();
            x.start ("wp:positionV").a ("relativeFrom", "page").start ("wp:posOffset").text (emu (r.y).to_string ()).end ().end ();
            x.start ("wp:extent").a ("cx", emu (double.max (1, r.w)).to_string ()).a ("cy", emu (double.max (1, r.h)).to_string ()).end ();
            x.start ("wp:effectExtent").ai ("l", 0).ai ("t", 0).ai ("r", 0).ai ("b", 0).end ();
            if (it.wrap.wraps ()) x.start ("wp:wrapSquare").a ("wrapText", "bothSides").end ();
            else x.empty ("wp:wrapNone");
            x.start ("wp:docPr").ai ("id", shape_id).a ("name", name != "" ? name : "Shape %d".printf (shape_id)).a ("descr", descr);
            if (it.alt_decorative) x.ai ("hidden", 0);
            x.end ();
            shape_id++;
            x.start ("wp:cNvGraphicFramePr").end ();
        }

        private void anchor_close (XmlOut x) {
            x.end ().end ().end ();
        }

        private void sp_pr (XmlOut x, Item it, double w, double h, string geom) {
            x.start ("wps:spPr");
            x.start ("a:xfrm");
            if (it.rotation != 0) x.a ("rot", ((long) Math.round (it.rotation * 60000)).to_string ());
            if (it.flip_h) x.ai ("flipH", 1);
            if (it.flip_v) x.ai ("flipV", 1);
            x.start ("a:off").ai ("x", 0).ai ("y", 0).end ();
            x.start ("a:ext").a ("cx", emu (w).to_string ()).a ("cy", emu (h).to_string ()).end ();
            x.end ();
            var s = it as ShapeItem;
            if (s != null && (s.shape == ShapeKind.PATH || s.shape == ShapeKind.POLYGON || s.shape == ShapeKind.STAR) && geom == "cust") {
                var pts = s.local_points ();
                x.start ("a:custGeom").empty ("a:avLst").empty ("a:gdLst").empty ("a:ahLst").empty ("a:cxnLst");
                x.start ("a:rect").a ("l", "0").a ("t", "0").a ("r", "r").a ("b", "b").end ();
                x.start ("a:pathLst").start ("a:path").a ("w", emu (w).to_string ()).a ("h", emu (h).to_string ());
                for (int i = 0; i < pts.size; i++) {
                    x.start (i == 0 ? "a:moveTo" : "a:lnTo").start ("a:pt").a ("x", emu (pts[i].x).to_string ()).a ("y", emu (pts[i].y).to_string ()).end ().end ();
                }
                if (s.closed || s.shape != ShapeKind.PATH) x.empty ("a:close");
                x.end ().end ().end ();
            } else {
                x.start ("a:prstGeom").a ("prst", geom).empty ("a:avLst").end ();
            }
            if (it.fill.kind == FillKind.SOLID && it.fill.color != ColorRef.NONE) {
                x.start ("a:solidFill").start ("a:srgbClr").a ("val", hex (it.fill.color));
                var c = pub.resolve_screen (it.fill.color);
                if (c.a < 0.999) x.start ("a:alpha").ai ("val", (int) Math.round (c.a * 100000)).end ();
                x.end ().end ();
            } else if ((it.fill.kind == FillKind.LINEAR || it.fill.kind == FillKind.RADIAL) && it.fill.stops.size >= 2) {
                x.start ("a:gradFill").start ("a:gsLst");
                foreach (var st in it.fill.stops) x.start ("a:gs").ai ("pos", (int) Math.round (st.offset * 100000)).start ("a:srgbClr").a ("val", hex (st.color)).end ().end ();
                x.end ();
                if (it.fill.kind == FillKind.LINEAR) x.start ("a:lin").ai ("ang", (int) Math.round (Math.fmod (it.fill.angle + 360, 360) * 60000)).ai ("scaled", 0).end ();
                else x.start ("a:path").a ("path", "circle").end ();
                x.end ();
            } else {
                x.empty ("a:noFill");
            }
            if (it.stroke.visible ()) {
                x.start ("a:ln").a ("w", emu (it.stroke.width).to_string ());
                x.start ("a:solidFill").start ("a:srgbClr").a ("val", hex (it.stroke.color)).end ().end ();
                if (it.stroke.dash != DashKind.SOLID) x.start ("a:prstDash").a ("val", it.stroke.dash == DashKind.DOT ? "sysDot" : (it.stroke.dash == DashKind.DASH ? "dash" : "dashDot")).end ();
                x.end ();
            } else {
                x.start ("a:ln").empty ("a:noFill").end ();
            }
            x.end ();
        }

        private void text_box (XmlOut x, TextFrame t, int page_index, bool master) {
            var res = master ? cache.master_story (t.story, page_index) : cache.story (t.story);
            var fr = res.frame_result (t.id);
            var box = t.box ();
            anchor_open (x, t, box, t.name, t.alt_text);
            x.start ("a:graphic").a ("xmlns:a", "http://schemas.openxmlformats.org/drawingml/2006/main");
            x.start ("a:graphicData").a ("uri", "http://schemas.microsoft.com/office/word/2010/wordprocessingShape");
            x.start ("wps:wsp");
            x.start ("wps:cNvSpPr").ai ("txBox", 1).end ();
            sp_pr (x, t, t.w, t.h, "rect");
            x.start ("wps:txbx").start ("w:txbxContent");
            if (fr != null && !fr.empty) story_body (x, pub.story (t.story).copy_range (fr.first, fr.last), page_index);
            else x.empty ("w:p");
            x.end ().end ();
            x.start ("wps:bodyPr").a ("rot", "0").a ("vert", t.vertical ? "vert" : "horz").a ("wrap", "square").a ("lIns", emu (t.inset_left).to_string ()).a ("tIns", emu (t.inset_top).to_string ()).a ("rIns", emu (t.inset_right).to_string ()).a ("bIns", emu (t.inset_bottom).to_string ()).a ("anchor", t.valign == 1 ? "ctr" : (t.valign == 2 ? "b" : "t"));
            if (t.columns > 1) x.ai ("numCol", t.columns).a ("spcCol", emu (t.gutter).to_string ());
            x.start ("a:noAutofit").end ();
            x.end ();
            x.end ().end ().end ();
            anchor_close (x);
        }

        private void shape_box (XmlOut x, ShapeItem s) {
            string geom;
            switch (s.shape) {
                case ShapeKind.ELLIPSE: geom = "ellipse"; break;
                case ShapeKind.LINE: geom = "line"; break;
                case ShapeKind.RECT: geom = s.corner == CornerKind.ROUNDED ? "roundRect" : "rect"; break;
                default: geom = "cust"; break;
            }
            anchor_open (x, s, s.box (), s.name, s.alt_text);
            x.start ("a:graphic").a ("xmlns:a", "http://schemas.openxmlformats.org/drawingml/2006/main");
            x.start ("a:graphicData").a ("uri", "http://schemas.microsoft.com/office/word/2010/wordprocessingShape");
            x.start ("wps:wsp");
            x.start ("wps:cNvSpPr").end ();
            sp_pr (x, s, s.w, s.h, geom);
            x.start ("wps:bodyPr").end ();
            x.end ().end ().end ();
            anchor_close (x);
        }

        private void picture (XmlOut x, Item it, Rect r, uint8[] data, string ext, string descr, double crop_l = 0, double crop_t = 0, double crop_r = 0, double crop_b = 0) {
            string rid = add_media (data, ext);
            anchor_open (x, it, r, it.name, descr);
            x.start ("a:graphic").a ("xmlns:a", "http://schemas.openxmlformats.org/drawingml/2006/main");
            x.start ("a:graphicData").a ("uri", "http://schemas.openxmlformats.org/drawingml/2006/picture");
            x.start ("pic:pic").a ("xmlns:pic", "http://schemas.openxmlformats.org/drawingml/2006/picture");
            x.start ("pic:nvPicPr").start ("pic:cNvPr").ai ("id", shape_id).a ("name", "Picture %d".printf (shape_id)).a ("descr", descr).end ().start ("pic:cNvPicPr").end ().end ();
            x.start ("pic:blipFill").start ("a:blip").a ("r:embed", rid).end ();
            if (crop_l > 0.0005 || crop_t > 0.0005 || crop_r > 0.0005 || crop_b > 0.0005) x.start ("a:srcRect").ai ("l", (int) Math.round (crop_l * 100000)).ai ("t", (int) Math.round (crop_t * 100000)).ai ("r", (int) Math.round (crop_r * 100000)).ai ("b", (int) Math.round (crop_b * 100000)).end ();
            x.start ("a:stretch").empty ("a:fillRect").end ();
            x.end ();
            x.start ("pic:spPr");
            x.start ("a:xfrm");
            if (it.rotation != 0 && !(it is GroupItem)) x.a ("rot", ((long) Math.round (it.rotation * 60000)).to_string ());
            x.start ("a:off").ai ("x", 0).ai ("y", 0).end ();
            x.start ("a:ext").a ("cx", emu (r.w).to_string ()).a ("cy", emu (r.h).to_string ()).end ();
            x.end ();
            var im = it as ImageFrame;
            x.start ("a:prstGeom").a ("prst", im != null && (im.shape_ellipse || im.clip_shape == "ellipse") ? "ellipse" : "rect").empty ("a:avLst").end ();
            if (im != null && im.stroke.visible ()) x.start ("a:ln").a ("w", emu (im.stroke.width).to_string ()).start ("a:solidFill").start ("a:srgbClr").a ("val", hex (im.stroke.color)).end ().end ().end ();
            x.end ();
            x.end ().end ().end ();
            anchor_close (x);
        }

        private uint8[] snapshot (Item it, bool master, int page_index, out Rect where) {
            double pad = 2;
            if (it.shadow.enabled) pad = double.max (pad, it.shadow.blur * 2 + 6);
            if (it.effects.glow) pad = double.max (pad, it.effects.glow_size * 2 + 4);
            var bb = it.bounds ();
            where = Rect (bb.x - pad, bb.y - pad, bb.w + 2 * pad, bb.h + 2 * pad);
            double sc = 3;
            var surf = new Cairo.ImageSurface (Cairo.Format.ARGB32, int.max (1, (int) Math.ceil (where.w * sc)), int.max (1, (int) Math.ceil (where.h * sc)));
            var cr = new Cairo.Context (surf);
            cr.scale (sc, sc);
            cr.translate (-where.x, -where.y);
            renderer.draw_item (cr, it, master, page_index);
            surf.flush ();
            return XpsExport.surface_png (surf);
        }

        private void item (XmlOut x, Item it, bool master, int page_index) {
            if (it.hidden || it.nonprinting) return;
            var layer = pub.layer (it.layer);
            if (layer != null && (!layer.visible || !layer.printable)) return;
            var g = it as GroupItem;
            if (g != null && !g.effects.any () && !g.shadow.enabled && g.rotation == 0) {
                foreach (var c in renderer.ordered (g.children)) item (x, c, master, page_index);
                return;
            }
            bool plain = !it.effects.any () && !it.shadow.enabled && !it.border_art.visible () && it.opacity > 0.999;
            var t = it as TextFrame;
            if (t != null && plain && (t.fill.kind == FillKind.NONE || t.fill.kind == FillKind.SOLID)) {
                text_box (x, t, page_index, master);
                return;
            }
            var im = it as ImageFrame;
            if (im != null && plain && !im.adjusted () && (im.clip_shape == "" || im.clip_shape == "ellipse") && im.merge_field == "") {
                var data = ImageStore.get_default ().bytes_for (pub, im);
                var inf = ImageStore.get_default ().info (pub, im);
                if (data != null && inf != null && !inf.vector) {
                    string ext = ImageStore.sniff (data);
                    if (ext == "png" || ext == "jpg" || ext == "gif" || ext == "bmp") {
                        var pl = ImageStore.place (im, inf);
                        double iw = inf.width * pl.sx, ih = inf.height * pl.sy;
                        double cl = (-pl.ox) / iw, ct = (-pl.oy) / ih;
                        double cr_ = (pl.ox + iw - im.w) / iw, cb = (pl.oy + ih - im.h) / ih;
                        picture (x, im, im.box (), data, ext, im.alt_decorative ? "" : im.alt_text, double.max (0, cl), double.max (0, ct), double.max (0, cr_), double.max (0, cb));
                        return;
                    }
                }
            }
            var s = it as ShapeItem;
            if (s != null && plain && !(s is WordArtItem) && (s.fill.kind == FillKind.NONE || s.fill.kind == FillKind.SOLID || s.fill.kind == FillKind.LINEAR || s.fill.kind == FillKind.RADIAL)) {
                shape_box (x, s);
                return;
            }
            var tb = it as TableItem;
            if (tb != null && plain && tb.rotation == 0) {
                table_box (x, tb, page_index);
                return;
            }
            Rect where;
            var png = snapshot (it, master, page_index, out where);
            string descr = it.alt_decorative ? "" : it.alt_text;
            var wa = it as WordArtItem;
            if (wa != null && descr == "") descr = wa.text;
            picture (x, it, where, png, "png", descr);
        }

        private void table_box (XmlOut x, TableItem tb, int page_index) {
            anchor_open (x, tb, tb.box (), tb.name, tb.alt_text);
            x.start ("a:graphic").a ("xmlns:a", "http://schemas.openxmlformats.org/drawingml/2006/main");
            x.start ("a:graphicData").a ("uri", "http://schemas.microsoft.com/office/word/2010/wordprocessingShape");
            x.start ("wps:wsp");
            x.start ("wps:cNvSpPr").ai ("txBox", 1).end ();
            sp_pr (x, tb, tb.w, tb.h, "rect");
            x.start ("wps:txbx").start ("w:txbxContent");
            x.start ("w:tbl");
            x.start ("w:tblPr").start ("w:tblW").ai ("w:w", twips (tb.w)).a ("w:type", "dxa").end ();
            if (tb.border_width > 0 && tb.border_color != ColorRef.NONE) {
                x.start ("w:tblBorders");
                foreach (string side in new string[] { "top", "left", "bottom", "right", "insideH", "insideV" }) x.start ("w:" + side).a ("w:val", "single").ai ("w:sz", (int) Math.round (tb.border_width * 8)).a ("w:color", hex (tb.border_color)).end ();
                x.end ();
            }
            x.start ("w:tblLayout").a ("w:type", "fixed").end ();
            x.end ();
            x.start ("w:tblGrid");
            foreach (var cw in tb.col_w) x.start ("w:gridCol").ai ("w:w", twips (cw)).end ();
            x.end ();
            for (int r = 0; r < tb.rows; r++) {
                x.start ("w:tr");
                x.start ("w:trPr");
                if (r < tb.header_rows) x.empty ("w:tblHeader");
                x.start ("w:trHeight").ai ("w:val", twips (tb.row_h[r])).a ("w:hRule", "atLeast").end ();
                x.end ();
                for (int c = 0; c < tb.cols; c++) {
                    var cell = tb.cells[r][c];
                    bool vcont = false;
                    if (cell.covered) {
                        bool owner_above = false;
                        for (int rr = r - 1; rr >= 0; rr--) {
                            var o = tb.cells[rr][c];
                            if (!o.covered && rr + o.row_span > r && o.col_span == 1) owner_above = true;
                            if (!o.covered) break;
                        }
                        if (!owner_above) continue;
                        vcont = true;
                    }
                    x.start ("w:tc").start ("w:tcPr");
                    double w = 0;
                    for (int k = c; k < c + cell.col_span && k < tb.cols; k++) w += tb.col_w[k];
                    x.start ("w:tcW").ai ("w:w", twips (w)).a ("w:type", "dxa").end ();
                    if (cell.col_span > 1) x.start ("w:gridSpan").ai ("w:val", cell.col_span).end ();
                    if (vcont) x.empty ("w:vMerge");
                    else if (cell.row_span > 1) x.start ("w:vMerge").a ("w:val", "restart").end ();
                    string fill = cell.fill;
                    if (fill == ColorRef.NONE) {
                        if (r < tb.header_rows && tb.header_fill != ColorRef.NONE) fill = tb.header_fill;
                        else if (r >= tb.header_rows && (r - tb.header_rows) % 2 == 1 && tb.alt_fill != ColorRef.NONE) fill = tb.alt_fill;
                    }
                    if (fill != ColorRef.NONE) x.start ("w:shd").a ("w:val", "clear").a ("w:color", "auto").a ("w:fill", hex (fill)).end ();
                    if (cell.diagonal == 1) x.start ("w:tcBorders").start ("w:tl2br").a ("w:val", "single").ai ("w:sz", 4).end ().end ();
                    if (cell.diagonal == 2) x.start ("w:tcBorders").start ("w:tr2bl").a ("w:val", "single").ai ("w:sz", 4).end ().end ();
                    x.start ("w:vAlign").a ("w:val", cell.valign == 1 ? "center" : (cell.valign == 2 ? "bottom" : "top")).end ();
                    x.end ();
                    if (vcont) x.empty ("w:p");
                    else story_body (x, cell.story, page_index);
                    x.end ();
                }
                x.end ();
            }
            x.end ();
            x.empty ("w:p");
            x.end ().end ();
            x.start ("wps:bodyPr").a ("lIns", "0").a ("tIns", "0").a ("rIns", "0").a ("bIns", "0").end ();
            x.end ().end ().end ();
            anchor_close (x);
        }

        public string document_xml () {
            var x = new XmlOut ();
            x.start ("w:document").a ("xmlns:w", W).a ("xmlns:r", "http://schemas.openxmlformats.org/officeDocument/2006/relationships").a ("xmlns:wp", "http://schemas.openxmlformats.org/drawingml/2006/wordprocessingDrawing").a ("xmlns:a", "http://schemas.openxmlformats.org/drawingml/2006/main").a ("xmlns:pic", "http://schemas.openxmlformats.org/drawingml/2006/picture").a ("xmlns:wps", "http://schemas.microsoft.com/office/word/2010/wordprocessingShape").a ("xmlns:mc", "http://schemas.openxmlformats.org/markup-compatibility/2006").a ("xmlns:wp14", "http://schemas.microsoft.com/office/word/2010/wordprocessingDrawing");
            x.start ("w:body");
            int bm = 0;
            for (int pi = 0; pi < pub.pages.size; pi++) {
                x.start ("w:p");
                if (pi > 0) x.start ("w:r").start ("w:br").a ("w:type", "page").end ().end ();
                x.start ("w:bookmarkStart").ai ("w:id", bm).a ("w:name", "page-%d".printf (pi + 1)).end ();
                x.start ("w:bookmarkEnd").ai ("w:id", bm++).end ();
                foreach (var b in pub.bookmarks) {
                    if (b.page != pi) continue;
                    x.start ("w:bookmarkStart").ai ("w:id", bm).a ("w:name", Renderer.dest_name (b.name)).end ();
                    x.start ("w:bookmarkEnd").ai ("w:id", bm++).end ();
                }
                var all = new Gee.ArrayList<Item> ();
                var masters = new Gee.HashSet<Item> ();
                foreach (var it in pub.master_items_for (pi)) {
                    all.add (it);
                    masters.add (it);
                }
                all.add_all (pub.pages[pi].items);
                foreach (var it in renderer.ordered (all)) item (x, it, masters.contains (it), pi);
                x.end ();
            }
            var s = pub.settings;
            x.start ("w:sectPr");
            x.start ("w:pgSz").ai ("w:w", twips (s.width)).ai ("w:h", twips (s.height));
            if (s.landscape ()) x.a ("w:orient", "landscape");
            x.end ();
            x.start ("w:pgMar").ai ("w:top", twips (s.margin_top)).ai ("w:right", twips (s.margin_outside)).ai ("w:bottom", twips (s.margin_bottom)).ai ("w:left", twips (s.margin_inside)).ai ("w:header", 0).ai ("w:footer", 0).ai ("w:gutter", 0).end ();
            x.end ();
            x.end ().end ();
            return x.finish ();
        }

        public uint8[] write () throws Error {
            string doc = document_xml ();
            string styles = styles_xml ();
            var zip = new ZipWriter ();
            var ct = new StringBuilder ("<?xml version=\"1.0\" encoding=\"UTF-8\" standalone=\"yes\"?>\n<Types xmlns=\"http://schemas.openxmlformats.org/package/2006/content-types\"><Default Extension=\"rels\" ContentType=\"application/vnd.openxmlformats-package.relationships+xml\"/><Default Extension=\"xml\" ContentType=\"application/xml\"/><Default Extension=\"png\" ContentType=\"image/png\"/><Default Extension=\"jpg\" ContentType=\"image/jpeg\"/><Default Extension=\"gif\" ContentType=\"image/gif\"/><Default Extension=\"bmp\" ContentType=\"image/bmp\"/>");
            ct.append ("<Override PartName=\"/word/document.xml\" ContentType=\"application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml\"/><Override PartName=\"/word/styles.xml\" ContentType=\"application/vnd.openxmlformats-officedocument.wordprocessingml.styles+xml\"/><Override PartName=\"/word/settings.xml\" ContentType=\"application/vnd.openxmlformats-officedocument.wordprocessingml.settings+xml\"/><Override PartName=\"/docProps/core.xml\" ContentType=\"application/vnd.openxmlformats-package.core-properties+xml\"/></Types>");
            zip.add_text ("[Content_Types].xml", ct.str);
            zip.add_text ("_rels/.rels", "<?xml version=\"1.0\" encoding=\"UTF-8\" standalone=\"yes\"?>\n<Relationships xmlns=\"http://schemas.openxmlformats.org/package/2006/relationships\"><Relationship Id=\"rId1\" Type=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument\" Target=\"word/document.xml\"/><Relationship Id=\"rId2\" Type=\"http://schemas.openxmlformats.org/package/2006/relationships/metadata/core-properties\" Target=\"docProps/core.xml\"/></Relationships>");
            var dr = new StringBuilder ("<?xml version=\"1.0\" encoding=\"UTF-8\" standalone=\"yes\"?>\n<Relationships xmlns=\"http://schemas.openxmlformats.org/package/2006/relationships\"><Relationship Id=\"rId1\" Type=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships/styles\" Target=\"styles.xml\"/><Relationship Id=\"rId2\" Type=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships/settings\" Target=\"settings.xml\"/>");
            foreach (string r in rels) dr.append (r);
            dr.append ("</Relationships>");
            zip.add_text ("word/_rels/document.xml.rels", dr.str);
            zip.add_text ("word/document.xml", doc);
            zip.add_text ("word/styles.xml", styles);
            zip.add_text ("word/settings.xml", "<?xml version=\"1.0\" encoding=\"UTF-8\" standalone=\"yes\"?>\n<w:settings xmlns:w=\"%s\"><w:compat><w:compatSetting w:name=\"compatibilityMode\" w:uri=\"http://schemas.microsoft.com/office/word\" w:val=\"15\"/></w:compat></w:settings>".printf (W));
            var core = new XmlOut ();
            core.start ("cp:coreProperties").a ("xmlns:cp", "http://schemas.openxmlformats.org/package/2006/metadata/core-properties").a ("xmlns:dc", "http://purl.org/dc/elements/1.1/").a ("xmlns:dcterms", "http://purl.org/dc/terms/").a ("xmlns:xsi", "http://www.w3.org/2001/XMLSchema-instance");
            if (pub.meta.title != "") core.element ("dc:title", pub.meta.title);
            if (pub.meta.author != "") core.element ("dc:creator", pub.meta.author);
            if (pub.meta.subject != "") core.element ("dc:subject", pub.meta.subject);
            core.start ("dcterms:created").a ("xsi:type", "dcterms:W3CDTF").text (new DateTime.now_utc ().format ("%Y-%m-%dT%H:%M:%SZ")).end ();
            core.end ();
            zip.add_text ("docProps/core.xml", core.finish ());
            for (int i = 0; i < media_names.size; i++) zip.add ("word/media/" + media_names[i], media_data[i].get_data (), false);
            return zip.finish ();
        }

        public static void export (Publication pub, string path) throws Error {
            var w = new DocxWriter (pub);
            FileUtils.set_data (path, w.write ());
        }
    }
}
