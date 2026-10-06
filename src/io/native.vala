namespace Singularity.Apps.Publish {

    public class NativeFormat {
        public const string MIME = "application/x-sinty-publication";
        public const string EXT = "spub";
        public const int VERSION = 1;

        public static Xml.Doc* parse_keep_space (string text) throws FormatError {
            Xml.Doc* doc = Xml.Parser.read_memory (text, text.length, null, null, Xml.ParserOption.NONET | Xml.ParserOption.HUGE);
            if (doc == null || doc->get_root_element () == null) {
                if (doc != null) delete doc;
                throw new FormatError.INVALID (_("The document contains malformed XML."));
            }
            return doc;
        }

        public static uint8[] write (Publication pub, bool thumbnail = true) throws Error {
            var zip = new ZipWriter ();
            zip.add_text ("mimetype", MIME, false);
            zip.add_text ("publication.xml", to_xml (pub));
            foreach (var e in pub.media.entries) zip.add ("media/" + e.key, e.value.get_data (), false);
            if (thumbnail && pub.pages.size > 0) {
                var hx = new HtmlExport (pub);
                hx.asset_prefix = "preview_files/";
                zip.add_text ("preview.html", hx.document (pub.meta.title != "" ? pub.meta.title : _("Publication")));
                foreach (var a in hx.assets) zip.add ("preview_files/" + a.name, a.data, false);
                var txt = new StringBuilder ();
                foreach (var st in Footnotes.stories_in_order (pub)) {
                    string t = st.plain_text ().replace (OBJ_STR, "").strip ();
                    if (t != "") txt.append (t + "\n\n");
                }
                zip.add_text ("content.txt", txt.str);
                try {
                    var ex = new Exporter (pub);
                    var surf = ex.thumbnail (0, 256);
                    var pb = Exporter.surface_to_pixbuf (surf, false);
                    uint8[] png;
                    pb.save_to_buffer (out png, "png");
                    zip.add ("Thumbnails/thumbnail.png", png, false);
                } catch (Error e) {
                }
            }
            return zip.finish ();
        }

        public static Publication read (uint8[] data) throws Error {
            var zip = new ZipReader (data);
            string? xml = zip.read_text ("publication.xml");
            if (xml == null) throw new FormatError.INVALID (_("The file is not a Publish document."));
            var pub = from_xml (xml);
            foreach (string name in zip.names ()) {
                if (!name.has_prefix ("media/") || name.length <= 6) continue;
                var bytes = zip.read (name);
                if (bytes != null) pub.media[name.substring (6)] = new Bytes (bytes);
            }
            return pub;
        }

        public static string to_xml (Publication pub) {
            var x = new XmlOut ();
            x.start ("publication").ai ("version", VERSION).ai ("next-id", pub.id_counter);
            var s = pub.settings;
            x.start ("settings").ad ("width", s.width).ad ("height", s.height).ai ("facing", s.facing ? 1 : 0).ai ("start-left", s.start_left ? 1 : 0);
            x.ad ("margin-top", s.margin_top).ad ("margin-bottom", s.margin_bottom).ad ("margin-inside", s.margin_inside).ad ("margin-outside", s.margin_outside);
            x.ai ("columns", s.columns).ad ("gutter", s.gutter);
            x.ad ("bleed-top", s.bleed_top).ad ("bleed-bottom", s.bleed_bottom).ad ("bleed-inside", s.bleed_inside).ad ("bleed-outside", s.bleed_outside).ad ("slug", s.slug);
            x.ad ("baseline-start", s.baseline_start).ad ("baseline-step", s.baseline_step).a ("units", s.units).ai ("cmyk", s.cmyk ? 1 : 0).a ("page-size", s.page_size).a ("impose", s.impose);
            x.a ("icc-profile", s.icc_profile).ai ("intent", s.intent).ai ("overprint-black", s.overprint_black ? 1 : 0).ai ("proof", s.proof ? 1 : 0).end ();
            var m = pub.meta;
            x.start ("meta").a ("title", m.title).a ("author", m.author).a ("subject", m.subject).a ("keywords", m.keywords).a ("created", m.created).a ("modified", m.modified).end ();
            x.start ("layers");
            foreach (var l in pub.layers) x.start ("layer").ai ("id", l.id).a ("name", l.name).ai ("visible", l.visible ? 1 : 0).ai ("locked", l.locked ? 1 : 0).ai ("printable", l.printable ? 1 : 0).a ("color", l.color).end ();
            x.end ();
            x.start ("swatches");
            foreach (var sw in pub.swatches) {
                x.start ("swatch").a ("name", sw.name).a ("model", sw.model.to_string ()).ai ("spot", sw.spot ? 1 : 0);
                x.ad ("r", sw.r).ad ("g", sw.g).ad ("b", sw.b).ad ("c", sw.c).ad ("m", sw.m).ad ("y", sw.y).ad ("k", sw.k);
                if (sw.group != "") x.a ("group", sw.group);
                if (sw.tint_of != "") x.a ("tint-of", sw.tint_of).ad ("tint", sw.tint);
                x.end ();
            }
            x.end ();
            x.start ("styles");
            foreach (var ps in pub.styles.paragraph) {
                x.start ("paragraph-style").a ("name", ps.name).a ("based-on", ps.based_on).a ("next", ps.next);
                if (ps.group != "") x.a ("group", ps.group);
                if (ps.tag != "") x.a ("tag", ps.tag);
                ps.para.write (x);
                x.start ("chars");
                ps.chars.write (x);
                x.end ();
                foreach (var n in ps.nested) n.write (x);
                foreach (var g in ps.grep) g.write (x);
                x.end ();
            }
            foreach (var cs in pub.styles.character) {
                x.start ("character-style").a ("name", cs.name).a ("based-on", cs.based_on);
                if (cs.group != "") x.a ("group", cs.group);
                cs.chars.write (x);
                x.end ();
            }
            x.end ();
            x.start ("sections");
            foreach (var sec in pub.sections) x.start ("section").ai ("start", sec.start_page).a ("prefix", sec.prefix).a ("name", sec.name).a ("style", sec.style.to_string ()).ai ("start-number", sec.start_number).ai ("continue", sec.continue_numbering ? 1 : 0).end ();
            x.end ();
            x.start ("masters");
            foreach (var mp in pub.masters) {
                x.start ("master").a ("id", mp.id).a ("name", mp.name).a ("based-on", mp.based_on);
                write_guides (x, mp.guides);
                x.start ("items");
                foreach (var it in mp.items) write_item (x, it);
                x.end ();
                x.start ("left-items");
                foreach (var it in mp.left_items) write_item (x, it);
                x.end ();
                x.end ();
            }
            x.end ();
            x.start ("stories");
            var ids = new Gee.ArrayList<int> ();
            ids.add_all (pub.stories.keys);
            ids.sort ((a, b) => a - b);
            foreach (int id in ids) {
                var st = pub.stories[id];
                x.start ("story").ai ("id", st.id).a ("frames", join_ints (st.frames));
                if (st.link_path != "") x.a ("link", st.link_path).a ("link-stamp", st.link_stamp);
                if (st.source_story != 0) x.ai ("source-story", st.source_story);
                write_paras (x, st);
                x.end ();
            }
            x.end ();
            x.start ("pages");
            foreach (var pg in pub.pages) {
                x.start ("page").ai ("id", pg.id).a ("master", pg.master).ai ("hide-master", pg.hide_master ? 1 : 0);
                if (!pg.width.is_nan ()) x.ad ("width", pg.width);
                if (!pg.height.is_nan ()) x.ad ("height", pg.height);
                if (pg.join_prev) x.ai ("join-prev", 1);
                if (pg.layout_name != "") x.a ("layout", pg.layout_name);
                if (pg.transition != "") x.a ("transition", pg.transition).ad ("transition-duration", pg.transition_duration);
                var ov = new Gee.ArrayList<int> ();
                ov.add_all (pg.overridden);
                ov.sort ((a, b) => a - b);
                x.a ("overridden", join_ints (ov));
                write_guides (x, pg.guides);
                x.start ("items");
                foreach (var it in pg.items) write_item (x, it);
                x.end ();
                x.end ();
            }
            x.end ();
            if (pub.bookmarks.size > 0) {
                x.start ("bookmarks");
                foreach (var b in pub.bookmarks) x.start ("bookmark").a ("name", b.name).ai ("page", b.page).ad ("x", b.x).ad ("y", b.y).end ();
                x.end ();
            }
            if (!pub.business.is_empty () || pub.business.set_name != "") pub.business.write (x);
            if (pub.color_scheme != "" || pub.font_scheme != "") x.start ("schemes").a ("color", pub.color_scheme).a ("font", pub.font_scheme).end ();
            if (pub.toc != null) pub.toc.write (x);
            if (pub.object_styles.size > 0) {
                x.start ("object-styles");
                foreach (var os in pub.object_styles) {
                    x.start ("object-style").a ("name", os.name).a ("based-on", os.based_on).a ("use", os.flags ()).a ("para-style", os.para_style);
                    write_item (x, os.proto);
                    x.end ();
                }
                x.end ();
            }
            if (!pub.footnotes.is_default ()) pub.footnotes.write (x);
            Conditions.write (pub, x);
            Review.write (pub, x);
            if (pub.table_styles.size > 0 || pub.cell_styles.size > 0) {
                x.start ("table-styles");
                foreach (var cs in pub.cell_styles) cs.write (x);
                foreach (var ts in pub.table_styles) ts.write (x);
                x.end ();
            }
            if (pub.endnote_story != 0) x.start ("endnotes").ai ("story", pub.endnote_story).end ();
            if (pub.xml_map != "") x.start ("xml-map").a ("tags", pub.xml_map).end ();
            if (pub.index != null) pub.index.write (x);
            if (pub.preflight_profiles.size > 0 || pub.preflight_profile != "") {
                x.start ("preflight").a ("profile", pub.preflight_profile);
                foreach (var pp in pub.preflight_profiles) pp.write (x);
                x.end ();
            }
            if (pub.text_vars.size > 0 || pub.chapter_number != 1) {
                x.start ("variables").ai ("chapter", pub.chapter_number);
                foreach (var v in pub.text_vars) v.write (x);
                x.end ();
            }
            if (pub.hyph_exceptions.size > 0) {
                x.start ("hyphenation-exceptions");
                foreach (var e in pub.hyph_exceptions.entries) x.start ("word").text (e.value).end ();
                x.end ();
            }
            if (pub.macros.size > 0) {
                x.start ("macros");
                foreach (var mc in pub.macros) {
                    x.start ("macro").a ("name", mc.name);
                    if (mc.event != "") x.a ("event", mc.event);
                    x.text (mc.script).end ();
                }
                x.end ();
            }
            var mg = pub.merge;
            x.start ("merge").a ("kind", mg.source_kind).a ("path", mg.source_path).ai ("preview", mg.preview).ai ("catalogue", mg.catalogue ? 1 : 0);
            x.ai ("rows", mg.cat_rows).ai ("cols", mg.cat_cols).ad ("x", mg.cat_x).ad ("y", mg.cat_y).ad ("w", mg.cat_w).ad ("h", mg.cat_h).ad ("gap-x", mg.cat_gap_x).ad ("gap-y", mg.cat_gap_y);
            if (mg.email_field != "") x.a ("email-field", mg.email_field);
            if (mg.email_subject != "") x.a ("email-subject", mg.email_subject);
            if (!mg.remove_blank_lines) x.ai ("keep-blank-lines", 1);
            if (mg.image_fit >= 0) x.ai ("image-fit", mg.image_fit);
            if (mg.hide_missing_images) x.ai ("hide-missing-images", 1);
            if (mg.excluded.size > 0) {
                var ex = new Gee.ArrayList<int> ();
                ex.add_all (mg.excluded);
                ex.sort ((a, b) => a - b);
                x.a ("excluded", join_ints (ex));
            }
            foreach (string f in mg.fields) x.start ("field").a ("name", f).end ();
            foreach (var fl in mg.filters) x.start ("filter").a ("field", fl.field).a ("op", fl.op.to_string ()).a ("value", fl.value).ai ("or", fl.or_previous ? 1 : 0).end ();
            foreach (var so in mg.sorts) x.start ("sort").a ("field", so.field).ai ("descending", so.descending ? 1 : 0).end ();
            foreach (var rec in mg.records) {
                x.start ("record");
                foreach (string v in rec) x.element ("v", v);
                x.end ();
            }
            x.end ();
            x.end ();
            return x.finish ();
        }

        public static string join_ints (Gee.List<int> l) {
            var sb = new StringBuilder ();
            foreach (int v in l) {
                if (sb.len > 0) sb.append (" ");
                sb.append (v.to_string ());
            }
            return sb.str;
        }

        public static Gee.ArrayList<int> split_ints (string? s) {
            var l = new Gee.ArrayList<int> ();
            if (s == null) return l;
            foreach (string p in s.split (" ")) {
                if (p.strip () == "") continue;
                l.add (int.parse (p));
            }
            return l;
        }

        private static string join_doubles (Gee.List<double?> l) {
            var sb = new StringBuilder ();
            foreach (var v in l) {
                if (sb.len > 0) sb.append (" ");
                sb.append (XmlOut.num (v));
            }
            return sb.str;
        }

        private static Gee.ArrayList<double?> split_doubles (string? s) {
            var l = new Gee.ArrayList<double?> ();
            if (s == null) return l;
            foreach (string p in s.split (" ")) {
                if (p.strip () == "") continue;
                l.add (Units.parse_num (p, 0));
            }
            return l;
        }

        private static void write_guides (XmlOut x, Gee.ArrayList<Guide> guides) {
            foreach (var g in guides) x.start ("guide").ai ("vertical", g.vertical ? 1 : 0).ad ("pos", g.pos).end ();
        }

        public static void write_paras (XmlOut x, Story st) {
            foreach (var p in st.paras) {
                x.start ("p").a ("style", p.style);
                if (p.anchor != "") x.a ("anchor", p.anchor);
                p.fmt.write (x);
                foreach (var r in p.runs) {
                    x.start ("r");
                    if (r.cstyle != "") x.a ("cstyle", r.cstyle);
                    if (r.condition != "") x.a ("condition", r.condition);
                    if (r.field != "") x.a ("field", r.field);
                    if (r.anchor_spec != null) x.ai ("anchor-mode", r.anchor_spec.mode).ai ("anchor-xref", r.anchor_spec.x_ref).ad ("anchor-dx", r.anchor_spec.x_offset).ad ("anchor-dy", r.anchor_spec.y_offset);
                    r.fmt.write (x);
                    if (r.anchor != null) write_item (x, r.anchor);
                    if (r.note != null) {
                        x.start ("note");
                        write_paras (x, r.note);
                        x.end ();
                    }
                    if (r.field == "") x.text (r.text);
                    x.end ();
                }
                x.end ();
            }
        }

        public static void read_paras (Xml.Node* n, Story st) {
            st.paras.clear ();
            foreach (var pn in XmlIn.elements (n, "p")) {
                var p = new Paragraph (XmlIn.attr (pn, "style") ?? StyleSheet.BASIC);
                p.anchor = XmlIn.attr (pn, "anchor") ?? "";
                p.fmt = ParaFormat.read (pn);
                foreach (var rn in XmlIn.elements (pn, "r")) {
                    string field = XmlIn.attr (rn, "field") ?? "";
                    var r = field != "" ? new Run.field_run (field) : new Run (XmlIn.text (rn));
                    if (field == AnchorSpec.FIELD) {
                        var spec = new AnchorSpec ();
                        spec.mode = XmlIn.int_attr (rn, "anchor-mode", 0);
                        spec.x_ref = XmlIn.int_attr (rn, "anchor-xref", 0);
                        spec.x_offset = XmlIn.double_attr (rn, "anchor-dx", 0);
                        spec.y_offset = XmlIn.double_attr (rn, "anchor-dy", 0);
                        r.anchor_spec = spec;
                        for (Xml.Node* c = rn->children; c != null; c = c->next) {
                            if (c->type != Xml.ElementType.ELEMENT_NODE) continue;
                            r.anchor = read_item (c);
                            if (r.anchor != null) break;
                        }
                        if (r.anchor == null) continue;
                    }
                    if (field == FootnoteOptions.FIELD || field == FootnoteOptions.END_FIELD) {
                        var nn = XmlIn.child (rn, "note");
                        r.note = new Story (0);
                        if (nn != null) read_paras (nn, r.note);
                    }
                    r.cstyle = XmlIn.attr (rn, "cstyle") ?? "";
                    r.condition = XmlIn.attr (rn, "condition") ?? "";
                    r.fmt = CharFormat.read (rn);
                    p.runs.add (r);
                }
                if (p.runs.size == 0) p.runs.add (new Run (""));
                st.paras.add (p);
            }
            if (st.paras.size == 0) st.paras.add (new Paragraph.with_text (""));
        }

        private static void write_common (XmlOut x, Item it) {
            x.ai ("id", it.id);
            if (it.name != "") x.a ("name", it.name);
            if (it.object_style != "") x.a ("object-style", it.object_style);
            x.ad ("x", it.x).ad ("y", it.y).ad ("w", it.w).ad ("h", it.h);
            if (it.rotation != 0) x.ad ("rotation", it.rotation);
            if (it.flip_h) x.ai ("flip-h", 1);
            if (it.flip_v) x.ai ("flip-v", 1);
            x.ai ("layer", it.layer);
            if (it.locked) x.ai ("locked", 1);
            if (it.hidden) x.ai ("hidden", 1);
            if (it.nonprinting) x.ai ("nonprinting", 1);
            if (it.opacity < 1) x.ad ("opacity", it.opacity);
            if (it.corner != CornerKind.NONE) x.ai ("corner", (int) it.corner).ad ("corner-radius", it.corner_radius);
            if (it.wrap != WrapMode.NONE) x.a ("wrap", it.wrap.to_string ()).ad ("wrap-offset", it.wrap_offset).ai ("wrap-side", (int) it.wrap_side);
            if (it.shape_ellipse) x.ai ("ellipse", 1);
            if (it.alt_text != "") x.a ("alt", it.alt_text);
            if (it.alt_decorative) x.ai ("decorative", 1);
            if (it.liquid_mode != 0 || it.liquid_pins != 0) x.ai ("liquid", it.liquid_mode).ai ("liquid-pins", it.liquid_pins);
            if (it.show_when != null) x.a ("when-field", it.show_when.field).a ("when-op", it.show_when.op.to_string ()).a ("when-value", it.show_when.value);
            if (it.link != "") x.a ("href", it.link);
            if (it.overprint_fill) x.ai ("overprint-fill", 1);
            if (it.overprint_stroke) x.ai ("overprint-stroke", 1);
            if (it.wrap_points.size > 0) x.a ("wrap-points", join_points (it.wrap_points));
            if (it.border_art.visible ()) x.a ("border-art", it.border_art.design).ad ("border-art-size", it.border_art.size).a ("border-art-color", it.border_art.color);
        }

        public static string join_points (Gee.List<Point?> pts) {
            var sb = new StringBuilder ();
            foreach (var p in pts) {
                if (sb.len > 0) sb.append (" ");
                sb.append ("%s,%s".printf (XmlOut.num (p.x), XmlOut.num (p.y)));
            }
            return sb.str;
        }

        public static Gee.ArrayList<Point?> split_points (string? s) {
            var l = new Gee.ArrayList<Point?> ();
            if (s == null) return l;
            foreach (string pp in s.split (" ")) {
                string[] xy = pp.split (",");
                if (xy.length == 2) l.add (Point (Units.parse_num (xy[0], 0), Units.parse_num (xy[1], 0)));
            }
            return l;
        }

        private static void write_style (XmlOut x, Item it) {
            var f = it.fill;
            if (f.kind != FillKind.NONE) {
                x.start ("fill").a ("kind", f.kind.to_string ()).a ("color", f.color).ad ("angle", f.angle);
                if (f.kind == FillKind.PATTERN) x.a ("pattern", f.pattern).a ("bg", f.bg_color);
                if (f.kind == FillKind.TEXTURE) x.a ("texture", f.texture);
                if (f.kind == FillKind.PICTURE) x.a ("media", f.media).a ("link", f.link);
                if (f.kind == FillKind.TEXTURE || f.kind == FillKind.PICTURE) x.ai ("tile", f.tile ? 1 : 0).ad ("tile-scale", f.tile_scale);
                foreach (var s in f.stops) x.start ("stop").ad ("offset", s.offset).a ("color", s.color).ad ("opacity", s.opacity).end ();
                x.end ();
            }
            var s = it.stroke;
            if (s.color != ColorRef.NONE) x.start ("stroke").a ("color", s.color).ad ("width", s.width).ai ("dash", (int) s.dash).ai ("cap", s.cap).ai ("join", s.join).ai ("arrow-start", s.arrow_start).ai ("arrow-end", s.arrow_end).end ();
            var sh = it.shadow;
            if (sh.enabled) x.start ("shadow").ad ("dx", sh.dx).ad ("dy", sh.dy).ad ("blur", sh.blur).a ("color", sh.color).ad ("opacity", sh.opacity).end ();
            it.effects.write (x);
            if (it.form != null && it.form.kind != FormKind.NONE) it.form.write (x);
        }

        public static void write_item (XmlOut x, Item it) {
            switch (it.kind) {
                case ItemKind.TEXT:
                    var t = (TextFrame) it;
                    x.start ("text");
                    write_common (x, it);
                    x.ai ("story", t.story).ai ("columns", t.columns).ad ("gutter", t.gutter);
                    x.ad ("inset-top", t.inset_top).ad ("inset-right", t.inset_right).ad ("inset-bottom", t.inset_bottom).ad ("inset-left", t.inset_left);
                    x.ai ("valign", t.valign).ai ("ignore-wrap", t.ignore_wrap ? 1 : 0).ai ("auto-height", t.auto_height ? 1 : 0);
                    if (t.autofit != 0) x.ai ("autofit", t.autofit);
                    if (t.vertical) x.ai ("vertical", 1);
                    if (t.own_grid) x.ai ("own-grid", 1).ad ("grid-start", t.grid_start).ad ("grid-step", t.grid_step).a ("grid-color", t.grid_color);
                    write_style (x, it);
                    x.end ();
                    break;
                case ItemKind.IMAGE:
                    var im = (ImageFrame) it;
                    x.start ("image");
                    write_common (x, it);
                    x.a ("link", im.link).a ("media", im.media).a ("fit", im.fit.to_string ());
                    x.ad ("img-x", im.img_x).ad ("img-y", im.img_y).ad ("img-scale", im.img_scale).ad ("focus-x", im.focus_x).ad ("focus-y", im.focus_y);
                    if (im.merge_field != "") x.a ("merge-field", im.merge_field);
                    if (im.link_stamp != "") x.a ("link-stamp", im.link_stamp);
                    if (Math.fabs (im.brightness) > 0.0001) x.ad ("brightness", im.brightness);
                    if (Math.fabs (im.contrast) > 0.0001) x.ad ("contrast", im.contrast);
                    if (im.recolor != 0) x.ai ("recolor", im.recolor).a ("recolor-color", im.recolor_color);
                    if (im.transparent_color != "") x.a ("transparent-color", im.transparent_color);
                    if (im.clip_shape != "") x.a ("clip-shape", im.clip_shape).ai ("clip-sides", im.clip_sides).ad ("clip-inset", im.clip_inset);
                    if (im.contour_source != 0) x.ai ("contour-source", im.contour_source);
                    if (im.clip_path) x.ai ("clip-path", 1);
                    if (im.pdf_page > 0) x.ai ("pdf-page", im.pdf_page);
                    write_style (x, it);
                    x.end ();
                    break;
                case ItemKind.SHAPE:
                    var s = (ShapeItem) it;
                    x.start ("shape");
                    write_common (x, it);
                    x.a ("shape", s.shape.to_string ()).ai ("sides", s.sides).ad ("star-inset", s.star_inset).ai ("line-reverse", s.line_reverse ? 1 : 0).ai ("closed", s.closed ? 1 : 0);
                    if (s.path_d != "") x.a ("path-d", s.path_d).ai ("even-odd", s.even_odd ? 1 : 0);
                    if (s.points.size > 0) {
                        var sb = new StringBuilder ();
                        foreach (var p in s.points) {
                            if (sb.len > 0) sb.append (" ");
                            sb.append ("%s,%s".printf (XmlOut.num (p.x), XmlOut.num (p.y)));
                        }
                        x.a ("points", sb.str);
                    }
                    var wa = it as WordArtItem;
                    if (wa != null) x.a ("text", wa.text).a ("font", wa.font).ai ("bold", wa.bold ? 1 : 0).ai ("italic", wa.italic ? 1 : 0).a ("warp", wa.warp.to_string ()).ad ("warp-amount", wa.warp_amount).ai ("even-height", wa.even_height ? 1 : 0);
                    write_style (x, it);
                    x.end ();
                    break;
                case ItemKind.TABLE:
                    var tb = (TableItem) it;
                    x.start ("table");
                    write_common (x, it);
                    x.ai ("rows", tb.rows).ai ("cols", tb.cols).a ("col-w", join_doubles (tb.col_w)).a ("row-h", join_doubles (tb.row_h));
                    x.ai ("header-rows", tb.header_rows).a ("border-color", tb.border_color).ad ("border-width", tb.border_width);
                    x.a ("header-fill", tb.header_fill).a ("alt-fill", tb.alt_fill).ad ("cell-inset", tb.cell_inset);
                    if (tb.table_style != "") x.a ("table-style", tb.table_style);
                    if (tb.link_path != "") x.a ("data-link", tb.link_path).ai ("data-sheet", tb.link_sheet).a ("data-stamp", tb.link_stamp);
                    if (tb.continue_to != 0) x.ai ("continue-to", tb.continue_to);
                    if (tb.continue_from != 0) x.ai ("continue-from", tb.continue_from);
                    if (!tb.repeat_header) x.ai ("repeat-header", 0);
                    write_style (x, it);
                    foreach (var row in tb.cells) {
                        x.start ("row");
                        foreach (var c in row) {
                            x.start ("cell").ai ("story", c.story.id).a ("fill", c.fill).ai ("row-span", c.row_span).ai ("col-span", c.col_span).ai ("covered", c.covered ? 1 : 0).ai ("valign", c.valign);
                            if (c.diagonal != 0) x.ai ("diagonal", c.diagonal);
                            if (c.cell_style != "") x.a ("cell-style", c.cell_style);
                            write_paras (x, c.story);
                            x.end ();
                        }
                        x.end ();
                    }
                    x.end ();
                    break;
                case ItemKind.GROUP:
                    var g = (GroupItem) it;
                    x.start ("group");
                    write_common (x, it);
                    write_style (x, it);
                    foreach (var c in g.children) write_item (x, c);
                    x.end ();
                    break;
            }
        }

        private static void read_common (Xml.Node* n, Item it) {
            it.id = XmlIn.int_attr (n, "id", 0);
            it.name = XmlIn.attr (n, "name") ?? "";
            it.object_style = XmlIn.attr (n, "object-style") ?? "";
            it.x = XmlIn.double_attr (n, "x", 0);
            it.y = XmlIn.double_attr (n, "y", 0);
            it.w = XmlIn.double_attr (n, "w", 10);
            it.h = XmlIn.double_attr (n, "h", 10);
            it.rotation = XmlIn.double_attr (n, "rotation", 0);
            it.flip_h = XmlIn.int_attr (n, "flip-h", 0) == 1;
            it.flip_v = XmlIn.int_attr (n, "flip-v", 0) == 1;
            it.layer = XmlIn.int_attr (n, "layer", 0);
            it.locked = XmlIn.int_attr (n, "locked", 0) == 1;
            it.hidden = XmlIn.int_attr (n, "hidden", 0) == 1;
            it.nonprinting = XmlIn.int_attr (n, "nonprinting", 0) == 1;
            it.opacity = XmlIn.double_attr (n, "opacity", 1);
            it.corner = (CornerKind) XmlIn.int_attr (n, "corner", 0);
            it.corner_radius = XmlIn.double_attr (n, "corner-radius", 0);
            it.wrap = WrapMode.parse (XmlIn.attr (n, "wrap") ?? "none");
            it.wrap_offset = XmlIn.double_attr (n, "wrap-offset", 6);
            it.wrap_side = (WrapSide) XmlIn.int_attr (n, "wrap-side", 0);
            it.shape_ellipse = XmlIn.int_attr (n, "ellipse", 0) == 1;
            it.alt_text = XmlIn.attr (n, "alt") ?? "";
            it.alt_decorative = XmlIn.int_attr (n, "decorative", 0) == 1;
            it.liquid_mode = XmlIn.int_attr (n, "liquid", 0);
            it.liquid_pins = XmlIn.int_attr (n, "liquid-pins", 0);
            string? wf = XmlIn.attr (n, "when-field");
            if (wf != null && wf != "") it.show_when = new MergeFilter (wf, FilterOp.parse (XmlIn.attr (n, "when-op") ?? "eq"), XmlIn.attr (n, "when-value") ?? "");
            it.link = XmlIn.attr (n, "href") ?? "";
            it.overprint_fill = XmlIn.int_attr (n, "overprint-fill", 0) == 1;
            it.overprint_stroke = XmlIn.int_attr (n, "overprint-stroke", 0) == 1;
            it.wrap_points = split_points (XmlIn.attr (n, "wrap-points"));
            it.border_art.design = XmlIn.attr (n, "border-art") ?? "";
            it.border_art.size = XmlIn.double_attr (n, "border-art-size", 18);
            it.border_art.color = XmlIn.attr (n, "border-art-color") ?? "";
            it.effects = Effects.read (n);
            it.form = FormSpec.read (n);
            var fn = XmlIn.child (n, "fill");
            if (fn != null) {
                var f = new Fill ();
                f.kind = FillKind.parse (XmlIn.attr (fn, "kind") ?? "none");
                f.color = XmlIn.attr (fn, "color") ?? "";
                f.angle = XmlIn.double_attr (fn, "angle", 90);
                foreach (var sn in XmlIn.elements (fn, "stop")) f.stops.add (new GradientStop (XmlIn.double_attr (sn, "offset", 0), XmlIn.attr (sn, "color") ?? "", XmlIn.double_attr (sn, "opacity", 1)));
                f.pattern = XmlIn.attr (fn, "pattern") ?? "";
                f.bg_color = XmlIn.attr (fn, "bg") ?? ColorRef.PAPER;
                f.texture = XmlIn.attr (fn, "texture") ?? "";
                f.media = XmlIn.attr (fn, "media") ?? "";
                f.link = XmlIn.attr (fn, "link") ?? "";
                f.tile = XmlIn.int_attr (fn, "tile", 0) == 1;
                f.tile_scale = XmlIn.double_attr (fn, "tile-scale", 1);
                it.fill = f;
            }
            var st = XmlIn.child (n, "stroke");
            if (st != null) {
                var s = new Stroke.with (XmlIn.attr (st, "color") ?? "", XmlIn.double_attr (st, "width", 1));
                s.dash = (DashKind) XmlIn.int_attr (st, "dash", 0);
                s.cap = XmlIn.int_attr (st, "cap", 0);
                s.join = XmlIn.int_attr (st, "join", 0);
                s.arrow_start = XmlIn.int_attr (st, "arrow-start", 0);
                s.arrow_end = XmlIn.int_attr (st, "arrow-end", 0);
                it.stroke = s;
            }
            var sh = XmlIn.child (n, "shadow");
            if (sh != null) {
                it.shadow.enabled = true;
                it.shadow.dx = XmlIn.double_attr (sh, "dx", 3);
                it.shadow.dy = XmlIn.double_attr (sh, "dy", 3);
                it.shadow.blur = XmlIn.double_attr (sh, "blur", 6);
                it.shadow.color = XmlIn.attr (sh, "color") ?? ColorRef.BLACK;
                it.shadow.opacity = XmlIn.double_attr (sh, "opacity", 0.35);
            }
        }

        public static Item? read_item (Xml.Node* n) {
            switch (n->name) {
                case "text":
                    var t = new TextFrame ();
                    read_common (n, t);
                    t.story = XmlIn.int_attr (n, "story", 0);
                    t.columns = XmlIn.int_attr (n, "columns", 1);
                    t.gutter = XmlIn.double_attr (n, "gutter", 12);
                    t.inset_top = XmlIn.double_attr (n, "inset-top", 0);
                    t.inset_right = XmlIn.double_attr (n, "inset-right", 0);
                    t.inset_bottom = XmlIn.double_attr (n, "inset-bottom", 0);
                    t.inset_left = XmlIn.double_attr (n, "inset-left", 0);
                    t.valign = XmlIn.int_attr (n, "valign", 0);
                    t.ignore_wrap = XmlIn.int_attr (n, "ignore-wrap", 0) == 1;
                    t.auto_height = XmlIn.int_attr (n, "auto-height", 0) == 1;
                    t.autofit = XmlIn.int_attr (n, "autofit", 0);
                    t.vertical = XmlIn.int_attr (n, "vertical", 0) == 1;
                    t.own_grid = XmlIn.int_attr (n, "own-grid", 0) == 1;
                    t.grid_start = XmlIn.double_attr (n, "grid-start", 0);
                    t.grid_step = XmlIn.double_attr (n, "grid-step", 12);
                    t.grid_color = XmlIn.attr (n, "grid-color") ?? "#99c2f2";
                    return t;
                case "image":
                    var im = new ImageFrame ();
                    read_common (n, im);
                    im.link = XmlIn.attr (n, "link") ?? "";
                    im.media = XmlIn.attr (n, "media") ?? "";
                    im.fit = FitMode.parse (XmlIn.attr (n, "fit") ?? "fill");
                    im.img_x = XmlIn.double_attr (n, "img-x", 0);
                    im.img_y = XmlIn.double_attr (n, "img-y", 0);
                    im.img_scale = XmlIn.double_attr (n, "img-scale", 1);
                    im.focus_x = XmlIn.double_attr (n, "focus-x", 0.5);
                    im.focus_y = XmlIn.double_attr (n, "focus-y", 0.5);
                    im.merge_field = XmlIn.attr (n, "merge-field") ?? "";
                    im.link_stamp = XmlIn.attr (n, "link-stamp") ?? "";
                    im.brightness = XmlIn.double_attr (n, "brightness", 0);
                    im.contrast = XmlIn.double_attr (n, "contrast", 0);
                    im.recolor = XmlIn.int_attr (n, "recolor", 0);
                    im.recolor_color = XmlIn.attr (n, "recolor-color") ?? "swatch:Blue";
                    im.transparent_color = XmlIn.attr (n, "transparent-color") ?? "";
                    im.clip_shape = XmlIn.attr (n, "clip-shape") ?? "";
                    im.clip_sides = XmlIn.int_attr (n, "clip-sides", 5);
                    im.clip_inset = XmlIn.double_attr (n, "clip-inset", 0.5);
                    im.contour_source = XmlIn.int_attr (n, "contour-source", 0);
                    im.clip_path = XmlIn.int_attr (n, "clip-path", 0) == 1;
                    im.pdf_page = XmlIn.int_attr (n, "pdf-page", 0);
                    return im;
                case "shape":
                    var kind = ShapeKind.parse (XmlIn.attr (n, "shape") ?? "rect");
                    ShapeItem s;
                    if (kind == ShapeKind.WORDART) {
                        var wa = new WordArtItem ();
                        wa.text = XmlIn.attr (n, "text") ?? "";
                        wa.font = XmlIn.attr (n, "font") ?? "Inter";
                        wa.bold = XmlIn.int_attr (n, "bold", 1) == 1;
                        wa.italic = XmlIn.int_attr (n, "italic", 0) == 1;
                        wa.warp = WarpKind.parse (XmlIn.attr (n, "warp") ?? "none");
                        wa.warp_amount = XmlIn.double_attr (n, "warp-amount", 0.5);
                        wa.even_height = XmlIn.int_attr (n, "even-height", 0) == 1;
                        s = wa;
                    } else {
                        s = new ShapeItem (kind);
                    }
                    read_common (n, s);
                    s.sides = XmlIn.int_attr (n, "sides", 6);
                    s.star_inset = XmlIn.double_attr (n, "star-inset", 0.5);
                    s.line_reverse = XmlIn.int_attr (n, "line-reverse", 0) == 1;
                    s.closed = XmlIn.int_attr (n, "closed", 1) == 1;
                    s.path_d = XmlIn.attr (n, "path-d") ?? "";
                    s.even_odd = XmlIn.int_attr (n, "even-odd", 0) == 1;
                    string? pts = XmlIn.attr (n, "points");
                    if (pts != null) foreach (string pp in pts.split (" ")) {
                        string[] xy = pp.split (",");
                        if (xy.length == 2) s.points.add (Point (Units.parse_num (xy[0], 0), Units.parse_num (xy[1], 0)));
                    }
                    return s;
                case "table":
                    var tb = new TableItem (XmlIn.int_attr (n, "rows", 1), XmlIn.int_attr (n, "cols", 1));
                    read_common (n, tb);
                    tb.col_w = split_doubles (XmlIn.attr (n, "col-w"));
                    tb.row_h = split_doubles (XmlIn.attr (n, "row-h"));
                    tb.header_rows = XmlIn.int_attr (n, "header-rows", 1);
                    tb.border_color = XmlIn.attr (n, "border-color") ?? ColorRef.BLACK;
                    tb.border_width = XmlIn.double_attr (n, "border-width", 0.5);
                    tb.header_fill = XmlIn.attr (n, "header-fill") ?? "";
                    tb.table_style = XmlIn.attr (n, "table-style") ?? "";
                    tb.link_path = XmlIn.attr (n, "data-link") ?? "";
                    tb.link_sheet = XmlIn.int_attr (n, "data-sheet", 0);
                    tb.link_stamp = XmlIn.attr (n, "data-stamp") ?? "";
                    tb.alt_fill = XmlIn.attr (n, "alt-fill") ?? "";
                    tb.cell_inset = XmlIn.double_attr (n, "cell-inset", 4);
                    tb.continue_to = XmlIn.int_attr (n, "continue-to", 0);
                    tb.continue_from = XmlIn.int_attr (n, "continue-from", 0);
                    tb.repeat_header = XmlIn.int_attr (n, "repeat-header", 1) == 1;
                    foreach (var rn in XmlIn.elements (n, "row")) {
                        var row = new Gee.ArrayList<Cell> ();
                        foreach (var cn in XmlIn.elements (rn, "cell")) {
                            var c = new Cell (XmlIn.int_attr (cn, "story", 0));
                            c.fill = XmlIn.attr (cn, "fill") ?? "";
                            c.row_span = XmlIn.int_attr (cn, "row-span", 1);
                            c.col_span = XmlIn.int_attr (cn, "col-span", 1);
                            c.covered = XmlIn.int_attr (cn, "covered", 0) == 1;
                            c.valign = XmlIn.int_attr (cn, "valign", 0);
                            c.diagonal = XmlIn.int_attr (cn, "diagonal", 0);
                            c.cell_style = XmlIn.attr (cn, "cell-style") ?? "";
                            read_paras (cn, c.story);
                            row.add (c);
                        }
                        tb.cells.add (row);
                    }
                    normalize_table (tb);
                    return tb;
                case "group":
                    var g = new GroupItem ();
                    read_common (n, g);
                    foreach (var cn in XmlIn.elements (n)) {
                        var c = read_item (cn);
                        if (c != null) g.children.add (c);
                    }
                    return g;
                default:
                    return null;
            }
        }

        public static void normalize_table (TableItem tb) {
            tb.rows = int.max (1, tb.cells.size);
            int cols = 1;
            foreach (var row in tb.cells) cols = int.max (cols, row.size);
            tb.cols = cols;
            int sid = 900000000;
            while (tb.cells.size < tb.rows) tb.cells.add (new Gee.ArrayList<Cell> ());
            foreach (var row in tb.cells) while (row.size < cols) row.add (new Cell (sid++));
            while (tb.col_w.size < cols) tb.col_w.add (tb.w / cols);
            while (tb.col_w.size > cols) tb.col_w.remove_at (tb.col_w.size - 1);
            while (tb.row_h.size < tb.rows) tb.row_h.add (tb.h / tb.rows);
            while (tb.row_h.size > tb.rows) tb.row_h.remove_at (tb.row_h.size - 1);
        }

        private static void read_items (Xml.Node* n, Gee.ArrayList<Item> list) {
            if (n == null) return;
            foreach (var c in XmlIn.elements (n)) {
                var it = read_item (c);
                if (it != null) list.add (it);
            }
        }

        private static void read_guides (Xml.Node* n, Gee.ArrayList<Guide> guides) {
            foreach (var g in XmlIn.elements (n, "guide")) guides.add (new Guide (XmlIn.int_attr (g, "vertical", 0) == 1, XmlIn.double_attr (g, "pos", 0)));
        }

        public static Publication from_xml (string xml) throws Error {
            Xml.Doc* doc = parse_keep_space (xml);
            try {
                var root = doc->get_root_element ();
                if (root->name != "publication") throw new FormatError.INVALID (_("The file is not a Publish document."));
                if (XmlIn.int_attr (root, "version", 1) > VERSION) throw new FormatError.UNSUPPORTED (_("The document was saved by a newer version of Publish."));
                var pub = new Publication ();
                pub.styles = new StyleSheet ();
                pub.id_counter = XmlIn.int_attr (root, "next-id", 1);
                var sn = XmlIn.child (root, "settings");
                if (sn != null) {
                    var s = pub.settings;
                    s.width = XmlIn.double_attr (sn, "width", s.width);
                    s.height = XmlIn.double_attr (sn, "height", s.height);
                    s.facing = XmlIn.int_attr (sn, "facing", 0) == 1;
                    s.start_left = XmlIn.int_attr (sn, "start-left", 0) == 1;
                    s.margin_top = XmlIn.double_attr (sn, "margin-top", s.margin_top);
                    s.margin_bottom = XmlIn.double_attr (sn, "margin-bottom", s.margin_bottom);
                    s.margin_inside = XmlIn.double_attr (sn, "margin-inside", s.margin_inside);
                    s.margin_outside = XmlIn.double_attr (sn, "margin-outside", s.margin_outside);
                    s.columns = XmlIn.int_attr (sn, "columns", 1);
                    s.gutter = XmlIn.double_attr (sn, "gutter", 12);
                    s.bleed_top = XmlIn.double_attr (sn, "bleed-top", 0);
                    s.bleed_bottom = XmlIn.double_attr (sn, "bleed-bottom", 0);
                    s.bleed_inside = XmlIn.double_attr (sn, "bleed-inside", 0);
                    s.bleed_outside = XmlIn.double_attr (sn, "bleed-outside", 0);
                    s.slug = XmlIn.double_attr (sn, "slug", 0);
                    s.baseline_start = XmlIn.double_attr (sn, "baseline-start", 36);
                    s.baseline_step = XmlIn.double_attr (sn, "baseline-step", 14);
                    s.units = XmlIn.attr (sn, "units") ?? "mm";
                    s.cmyk = XmlIn.int_attr (sn, "cmyk", 1) == 1;
                    s.page_size = XmlIn.attr (sn, "page-size") ?? "";
                    s.impose = XmlIn.attr (sn, "impose") ?? "";
                    s.icc_profile = XmlIn.attr (sn, "icc-profile") ?? "";
                    s.intent = XmlIn.int_attr (sn, "intent", 1);
                    s.overprint_black = XmlIn.int_attr (sn, "overprint-black", 1) == 1;
                    s.proof = XmlIn.int_attr (sn, "proof", 0) == 1;
                }
                var mn = XmlIn.child (root, "meta");
                if (mn != null) {
                    pub.meta.title = XmlIn.attr (mn, "title") ?? "";
                    pub.meta.author = XmlIn.attr (mn, "author") ?? "";
                    pub.meta.subject = XmlIn.attr (mn, "subject") ?? "";
                    pub.meta.keywords = XmlIn.attr (mn, "keywords") ?? "";
                    pub.meta.created = XmlIn.attr (mn, "created") ?? "";
                    pub.meta.modified = XmlIn.attr (mn, "modified") ?? "";
                }
                foreach (var ln in XmlIn.elements (XmlIn.child (root, "layers"), "layer")) {
                    var l = new Layer (XmlIn.int_attr (ln, "id", 0), XmlIn.attr (ln, "name") ?? "");
                    l.visible = XmlIn.int_attr (ln, "visible", 1) == 1;
                    l.locked = XmlIn.int_attr (ln, "locked", 0) == 1;
                    l.printable = XmlIn.int_attr (ln, "printable", 1) == 1;
                    l.color = XmlIn.attr (ln, "color") ?? "#4a86e8";
                    pub.layers.add (l);
                }
                if (pub.layers.size == 0) pub.layers.add (new Layer (pub.next_id (), _("Layer 1")));
                foreach (var wn in XmlIn.elements (XmlIn.child (root, "swatches"), "swatch")) {
                    var sw = new Swatch.rgb (XmlIn.attr (wn, "name") ?? "", XmlIn.double_attr (wn, "r", 0), XmlIn.double_attr (wn, "g", 0), XmlIn.double_attr (wn, "b", 0));
                    sw.model = ColorModel.parse (XmlIn.attr (wn, "model") ?? "rgb");
                    sw.spot = XmlIn.int_attr (wn, "spot", 0) == 1;
                    sw.c = XmlIn.double_attr (wn, "c", 0);
                    sw.m = XmlIn.double_attr (wn, "m", 0);
                    sw.y = XmlIn.double_attr (wn, "y", 0);
                    sw.k = XmlIn.double_attr (wn, "k", 0);
                    sw.group = XmlIn.attr (wn, "group") ?? "";
                    sw.tint_of = XmlIn.attr (wn, "tint-of") ?? "";
                    sw.tint = XmlIn.double_attr (wn, "tint", 100);
                    pub.swatches.add (sw);
                }
                var stn = XmlIn.child (root, "styles");
                foreach (var pn in XmlIn.elements (stn, "paragraph-style")) {
                    var ps = new ParagraphStyle (XmlIn.attr (pn, "name") ?? "", XmlIn.attr (pn, "based-on") ?? "");
                    ps.next = XmlIn.attr (pn, "next") ?? "";
                    ps.group = XmlIn.attr (pn, "group") ?? "";
                    ps.tag = XmlIn.attr (pn, "tag") ?? "";
                    ps.para = ParaFormat.read (pn);
                    var cn = XmlIn.child (pn, "chars");
                    if (cn != null) ps.chars = CharFormat.read (cn);
                    foreach (var nn in XmlIn.elements (pn, "nested")) ps.nested.add (NestedStyle.read (nn));
                    foreach (var gn in XmlIn.elements (pn, "grep-style")) ps.grep.add (GrepStyle.read (gn));
                    pub.styles.paragraph.add (ps);
                }
                foreach (var cn in XmlIn.elements (stn, "character-style")) {
                    var cs = new CharacterStyle (XmlIn.attr (cn, "name") ?? "", XmlIn.attr (cn, "based-on") ?? "");
                    cs.chars = CharFormat.read (cn);
                    cs.group = XmlIn.attr (cn, "group") ?? "";
                    pub.styles.character.add (cs);
                }
                if (pub.styles.find_paragraph (StyleSheet.BASIC) == null) pub.styles.paragraph.insert (0, StyleSheet.standard ().paragraph[0]);
                foreach (var sec in XmlIn.elements (XmlIn.child (root, "sections"), "section")) {
                    var s = new Section (XmlIn.int_attr (sec, "start", 0));
                    s.prefix = XmlIn.attr (sec, "prefix") ?? "";
                    s.name = XmlIn.attr (sec, "name") ?? "";
                    s.style = NumberStyle.parse (XmlIn.attr (sec, "style") ?? "arabic");
                    s.start_number = XmlIn.int_attr (sec, "start-number", 1);
                    s.continue_numbering = XmlIn.int_attr (sec, "continue", 0) == 1;
                    pub.sections.add (s);
                }
                if (pub.sections.size == 0) pub.sections.add (new Section (0));
                foreach (var mpn in XmlIn.elements (XmlIn.child (root, "masters"), "master")) {
                    var mp = new MasterPage (XmlIn.attr (mpn, "id") ?? "A", XmlIn.attr (mpn, "name") ?? "");
                    mp.based_on = XmlIn.attr (mpn, "based-on") ?? "";
                    read_guides (mpn, mp.guides);
                    read_items (XmlIn.child (mpn, "items"), mp.items);
                    read_items (XmlIn.child (mpn, "left-items"), mp.left_items);
                    pub.masters.add (mp);
                }
                foreach (var stn2 in XmlIn.elements (XmlIn.child (root, "stories"), "story")) {
                    var st = new Story (XmlIn.int_attr (stn2, "id", 0));
                    st.frames = split_ints (XmlIn.attr (stn2, "frames"));
                    st.link_path = XmlIn.attr (stn2, "link") ?? "";
                    st.link_stamp = XmlIn.attr (stn2, "link-stamp") ?? "";
                    st.source_story = XmlIn.int_attr (stn2, "source-story", 0);
                    read_paras (stn2, st);
                    pub.stories[st.id] = st;
                }
                foreach (var pgn in XmlIn.elements (XmlIn.child (root, "pages"), "page")) {
                    var pg = new Page (XmlIn.int_attr (pgn, "id", 0));
                    pg.master = XmlIn.attr (pgn, "master") ?? "";
                    pg.hide_master = XmlIn.int_attr (pgn, "hide-master", 0) == 1;
                    pg.width = XmlIn.double_attr (pgn, "width", double.NAN);
                    pg.height = XmlIn.double_attr (pgn, "height", double.NAN);
                    pg.join_prev = XmlIn.int_attr (pgn, "join-prev", 0) == 1;
                    pg.transition = XmlIn.attr (pgn, "transition") ?? "";
                    pg.layout_name = XmlIn.attr (pgn, "layout") ?? "";
                    pg.transition_duration = XmlIn.double_attr (pgn, "transition-duration", 1);
                    foreach (int v in split_ints (XmlIn.attr (pgn, "overridden"))) pg.overridden.add (v);
                    read_guides (pgn, pg.guides);
                    read_items (XmlIn.child (pgn, "items"), pg.items);
                    pub.pages.add (pg);
                }
                foreach (var bn in XmlIn.elements (XmlIn.child (root, "bookmarks"), "bookmark")) pub.bookmarks.add (new Bookmark (XmlIn.attr (bn, "name") ?? "", XmlIn.int_attr (bn, "page", 0), XmlIn.double_attr (bn, "x", 0), XmlIn.double_attr (bn, "y", 0)));
                var bizn = XmlIn.child (root, "business");
                if (bizn != null) pub.business = BusinessInfo.read (bizn);
                var schn = XmlIn.child (root, "schemes");
                if (schn != null) {
                    pub.color_scheme = XmlIn.attr (schn, "color") ?? "";
                    pub.font_scheme = XmlIn.attr (schn, "font") ?? "";
                }
                var tocn = XmlIn.child (root, "toc");
                if (tocn != null) pub.toc = TocSettings.read (tocn);
                foreach (var osn in XmlIn.elements (XmlIn.child (root, "object-styles"), "object-style")) {
                    var os = new ObjectStyle (XmlIn.attr (osn, "name") ?? "");
                    os.based_on = XmlIn.attr (osn, "based-on") ?? "";
                    os.set_flags (XmlIn.attr (osn, "use") ?? "");
                    os.para_style = XmlIn.attr (osn, "para-style") ?? "";
                    var tn = XmlIn.child (osn, "text");
                    if (tn != null) {
                        var proto = read_item (tn) as TextFrame;
                        if (proto != null) os.proto = proto;
                    }
                    pub.object_styles.add (os);
                }
                var tsn = XmlIn.child (root, "table-styles");
                if (tsn != null) {
                    foreach (var cn in XmlIn.elements (tsn, "cell-style")) pub.cell_styles.add (CellStyle.read (cn));
                    foreach (var tn in XmlIn.elements (tsn, "table-style")) pub.table_styles.add (TableStyle.read (tn));
                }
                Conditions.read (pub, XmlIn.child (root, "conditions"));
                Review.read (pub, XmlIn.child (root, "review"));
                var fnn = XmlIn.child (root, "footnotes");
                if (fnn != null) pub.footnotes = FootnoteOptions.read (fnn);
                var enn = XmlIn.child (root, "endnotes");
                if (enn != null) pub.endnote_story = XmlIn.int_attr (enn, "story", 0);
                var xmn = XmlIn.child (root, "xml-map");
                if (xmn != null) pub.xml_map = XmlIn.attr (xmn, "tags") ?? "";
                var ixn = XmlIn.child (root, "index");
                if (ixn != null) pub.index = IndexSettings.read (ixn);
                var pfn = XmlIn.child (root, "preflight");
                if (pfn != null) {
                    pub.preflight_profile = XmlIn.attr (pfn, "profile") ?? "";
                    foreach (var ppn in XmlIn.elements (pfn, "preflight-profile")) pub.preflight_profiles.add (PreflightProfile.read (ppn));
                }
                var varn = XmlIn.child (root, "variables");
                if (varn != null) {
                    pub.chapter_number = XmlIn.int_attr (varn, "chapter", 1);
                    foreach (var vn in XmlIn.elements (varn, "variable")) pub.text_vars.add (TextVariable.read (vn));
                }
                foreach (var hw in XmlIn.elements (XmlIn.child (root, "hyphenation-exceptions"), "word")) {
                    string w = XmlIn.text (hw).strip ();
                    if (w != "") pub.hyph_exceptions[w.replace ("-", "").replace ("~", "").down ()] = w;
                }
                foreach (var macn in XmlIn.elements (XmlIn.child (root, "macros"), "macro")) {
                    var md = new MacroDef (XmlIn.attr (macn, "name") ?? "", XmlIn.text (macn));
                    md.event = XmlIn.attr (macn, "event") ?? "";
                    pub.macros.add (md);
                }
                var mgn = XmlIn.child (root, "merge");
                if (mgn != null) {
                    var mg = pub.merge;
                    mg.source_kind = XmlIn.attr (mgn, "kind") ?? "";
                    mg.source_path = XmlIn.attr (mgn, "path") ?? "";
                    mg.preview = XmlIn.int_attr (mgn, "preview", -1);
                    mg.catalogue = XmlIn.int_attr (mgn, "catalogue", 0) == 1;
                    mg.cat_rows = XmlIn.int_attr (mgn, "rows", 2);
                    mg.cat_cols = XmlIn.int_attr (mgn, "cols", 2);
                    mg.cat_x = XmlIn.double_attr (mgn, "x", 36);
                    mg.cat_y = XmlIn.double_attr (mgn, "y", 36);
                    mg.cat_w = XmlIn.double_attr (mgn, "w", 200);
                    mg.cat_h = XmlIn.double_attr (mgn, "h", 200);
                    mg.cat_gap_x = XmlIn.double_attr (mgn, "gap-x", 0);
                    mg.cat_gap_y = XmlIn.double_attr (mgn, "gap-y", 0);
                    foreach (var fn in XmlIn.elements (mgn, "field")) mg.fields.add (XmlIn.attr (fn, "name") ?? "");
                    mg.email_field = XmlIn.attr (mgn, "email-field") ?? "";
                    mg.email_subject = XmlIn.attr (mgn, "email-subject") ?? "";
                    mg.remove_blank_lines = XmlIn.int_attr (mgn, "keep-blank-lines", 0) == 0;
                    mg.image_fit = XmlIn.int_attr (mgn, "image-fit", -1);
                    mg.hide_missing_images = XmlIn.int_attr (mgn, "hide-missing-images", 0) == 1;
                    foreach (int v in split_ints (XmlIn.attr (mgn, "excluded"))) mg.excluded.add (v);
                    foreach (var fln in XmlIn.elements (mgn, "filter")) mg.filters.add (new MergeFilter (XmlIn.attr (fln, "field") ?? "", FilterOp.parse (XmlIn.attr (fln, "op") ?? "eq"), XmlIn.attr (fln, "value") ?? "", XmlIn.int_attr (fln, "or", 0) == 1));
                    foreach (var son in XmlIn.elements (mgn, "sort")) mg.sorts.add (new MergeSort (XmlIn.attr (son, "field") ?? "", XmlIn.int_attr (son, "descending", 0) == 1));
                    foreach (var rn in XmlIn.elements (mgn, "record")) {
                        var rec = new Gee.ArrayList<string> ();
                        foreach (var vn in XmlIn.elements (rn, "v")) rec.add (XmlIn.text (vn));
                        mg.records.add (rec);
                    }
                }
                if (pub.pages.size == 0) pub.add_page (-1, pub.masters.size > 0 ? pub.masters[0].id : "");
                int max_id = pub.id_counter;
                pub.walk ((r) => {
                    max_id = int.max (max_id, r.item.id + 1);
                    return true;
                });
                foreach (var k in pub.stories.keys) max_id = int.max (max_id, k + 1);
                pub.id_counter = max_id;
                return pub;
            } finally {
                delete doc;
            }
        }
    }
}
