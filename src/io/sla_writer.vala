namespace Singularity.Apps.Publish {

    public class SlaWriter {
        public Publication pub;
        public Gee.ArrayList<string> warnings = new Gee.ArrayList<string> ();
        private Gee.HashMap<string, string> adhoc = new Gee.HashMap<string, string> ();
        private Gee.ArrayList<string> adhoc_order = new Gee.ArrayList<string> ();
        private Gee.HashSet<string> warned = new Gee.HashSet<string> ();
        private const double GAP = 40;
        private const double ORIGIN_X = 100;
        private const double ORIGIN_Y = 20;
        private const double KAPPA = 0.5522847498;

        public SlaWriter (Publication pub) {
            this.pub = pub;
        }

        private void warn (string msg) {
            if (warned.contains (msg)) return;
            warned.add (msg);
            warnings.add (msg);
        }

        private static string n (double v) {
            return XmlOut.num (Math.round (v * 10000) / 10000);
        }

        public static uint8[] qt_compress (uint8[] data) throws Error {
            var conv = new ZlibCompressor (ZlibCompressorFormat.ZLIB, 9);
            var input = new MemoryInputStream.from_data (data, null);
            var stream = new ConverterInputStream (input, conv);
            var outp = new MemoryOutputStream.resizable ();
            outp.splice (stream, OutputStreamSpliceFlags.CLOSE_SOURCE | OutputStreamSpliceFlags.CLOSE_TARGET);
            uint8[] z = outp.steal_as_bytes ().get_data ();
            var result = new uint8[z.length + 4];
            uint len = data.length;
            result[0] = (uint8) ((len >> 24) & 0xff);
            result[1] = (uint8) ((len >> 16) & 0xff);
            result[2] = (uint8) ((len >> 8) & 0xff);
            result[3] = (uint8) (len & 0xff);
            Memory.copy (&result[4], z, z.length);
            return result;
        }

        private void color_attr (XmlOut x, string attr, string shade_attr, string? spec) {
            string name;
            double shade;
            resolve_color (spec, out name, out shade);
            x.a (attr, name);
            if (shade_attr != "") x.a (shade_attr, n (shade));
        }

        private void resolve_color (string? spec, out string name, out double shade) {
            shade = 100;
            if (spec == null || spec == ColorRef.NONE) {
                name = "None";
                return;
            }
            if (ColorRef.is_swatch (spec)) {
                name = ColorRef.swatch_name (spec);
                shade = ColorRef.tint_of (spec);
                if (pub.swatch (name) == null) name = "Black";
                return;
            }
            if (adhoc.has_key (spec)) {
                name = adhoc[spec];
                return;
            }
            name = spec.has_prefix ("cmyk:") ? "FromPublish " + spec.substring (5) : "FromPublish " + spec;
            adhoc[spec] = name;
            adhoc_order.add (spec);
        }

        private static string font_name (string family, bool bold, bool italic) {
            if (bold && italic) return family + " Bold Italic";
            if (bold) return family + " Bold";
            if (italic) return family + " Italic";
            return family + " Regular";
        }

        private void write_char_attrs (XmlOut x, CharFormat f, CharFormat? resolved) {
            if (f.font != null || f.bold >= 0 || f.italic >= 0) {
                string fam = f.font ?? (resolved != null && resolved.font != null ? resolved.font : "Inter");
                bool b = f.bold >= 0 ? f.bold == 1 : (resolved != null && resolved.bold == 1);
                bool i = f.italic >= 0 ? f.italic == 1 : (resolved != null && resolved.italic == 1);
                x.a ("FONT", font_name (fam, b, i));
            }
            if (!f.size.is_nan ()) x.a ("FONTSIZE", n (f.size));
            if (f.color != null) color_attr (x, "FCOLOR", "FSHADE", f.color);
            if (f.underline >= 0 || f.strike >= 0 || f.caps >= 0 || f.position >= 0) {
                var feats = new Gee.ArrayList<string> ();
                bool explicit_off = f.underline == 0 || f.strike == 0 || f.caps == 0 || f.position == 0;
                if (!explicit_off) feats.add ("inherit");
                if (f.underline == 1) feats.add ("underline");
                if (f.strike == 1) feats.add ("strike");
                if (f.position == 1) feats.add ("superscript");
                if (f.position == 2) feats.add ("subscript");
                if (f.caps == 1) feats.add ("allcaps");
                if (f.caps == 2) feats.add ("smallcaps");
                x.a ("FEATURES", string.joinv (" ", feats.to_array ()));
            }
            if (!f.tracking.is_nan ()) x.a ("KERN", n (f.tracking / 10));
            if (!f.baseline_shift.is_nan () && f.baseline_shift != 0) {
                double size = f.size.is_nan () ? (resolved != null ? resolved.size : 12) : f.size;
                x.a ("BASEO", n (f.baseline_shift / size * 1000));
            }
            if (f.lang != null && f.lang != "") x.a ("LANGUAGE", f.lang);
        }

        private void write_para_attrs (XmlOut x, ParaFormat p) {
            if (p.align >= 0) x.ai ("ALIGN", p.align.clamp (0, 4));
            if (p.align_grid == 1) {
                x.ai ("LINESPMode", 2);
                if (!p.leading.is_nan ()) x.a ("LINESP", n (p.leading));
            } else if (!p.leading.is_nan ()) {
                if (p.leading <= 0.01) x.ai ("LINESPMode", 1);
                else {
                    x.ai ("LINESPMode", 0);
                    x.a ("LINESP", n (p.leading));
                }
            }
            if (!p.left_indent.is_nan ()) x.a ("INDENT", n (p.left_indent));
            if (!p.right_indent.is_nan ()) x.a ("RMARGIN", n (p.right_indent));
            if (!p.first_indent.is_nan ()) x.a ("FIRST", n (p.first_indent));
            if (!p.space_before.is_nan ()) x.a ("VOR", n (p.space_before));
            if (!p.space_after.is_nan ()) x.a ("NACH", n (p.space_after));
            if (p.drop_lines >= 0) {
                x.ai ("DROP", p.drop_lines >= 2 ? 1 : 0);
                if (p.drop_lines >= 2) x.ai ("DROPLIN", p.drop_lines);
                if (p.drop_chars > 1) warn (_("Scribus drop caps span a single character."));
            }
            if (p.keep_next >= 0) x.ai ("KeepWithNext", p.keep_next);
            if (p.keep_lines >= 0) x.ai ("KeepTogether", p.keep_lines);
            if (p.list_type >= 0) {
                x.ai ("Bullet", p.list_type == 1 ? 1 : 0);
                x.ai ("Numeration", p.list_type == 2 ? 1 : 0);
                if (p.list_type == 1 && p.bullet != null) x.a ("BulletStr", p.bullet);
                if (p.list_type == 2) {
                    int fmt;
                    switch (p.number_format) {
                        case 5: fmt = 1; break;
                        case 4: fmt = 2; break;
                        case 3: fmt = 3; break;
                        case 2: fmt = 4; break;
                        default: fmt = 0; break;
                    }
                    x.ai ("NumerationFormat", fmt);
                    if (p.number_start >= 0) x.ai ("NumerationStart", p.number_start);
                    if (p.list_level >= 0) x.ai ("NumerationLevel", p.list_level);
                }
            }
            if (p.rule_above != null && p.rule_above != "" || p.rule_below != null && p.rule_below != "") warn (_("Paragraph rules are not written to Scribus files."));
        }

        private void write_tabs (XmlOut x, ParaFormat p) {
            if (p.tabs == null || p.tabs == "") return;
            foreach (var t in TabStop.parse (p.tabs)) {
                int type;
                switch (t.kind) {
                    case TabKind.RIGHT: type = 1; break;
                    case TabKind.DECIMAL: type = 2; break;
                    case TabKind.CENTER: type = 4; break;
                    default: type = 0; break;
                }
                x.start ("Tabs").ai ("Type", type).a ("Pos", n (t.pos)).a ("Fill", t.leader).end ();
            }
        }

        private CharFormat resolved_style_chars (string style) {
            var pf = ParaFormat.defaults ();
            var cf = CharFormat.defaults ();
            pub.styles.resolve_paragraph (style, pf, cf);
            return cf;
        }

        private CharFormat resolved_char_style (string name) {
            var cf = CharFormat.defaults ();
            pub.styles.resolve_character (name, cf);
            return cf;
        }

        private void write_styles (XmlOut x) {
            var basic = pub.styles.find_paragraph (StyleSheet.BASIC);
            var bp = ParaFormat.defaults ();
            var bc = CharFormat.defaults ();
            if (basic != null) {
                bp.apply (basic.para);
                bc.apply (basic.chars);
            }
            x.start ("STYLE").a ("NAME", "Default Paragraph Style").ai ("DefaultStyle", 1);
            write_para_attrs (x, bp);
            write_char_attrs (x, bc, bc);
            write_tabs (x, bp);
            x.end ();
            foreach (var ps in pub.styles.paragraph) {
                if (ps.name == StyleSheet.BASIC) continue;
                x.start ("STYLE").a ("NAME", ps.name);
                if (ps.based_on != "" && ps.based_on != StyleSheet.BASIC) x.a ("PARENT", ps.based_on);
                write_para_attrs (x, ps.para);
                write_char_attrs (x, ps.chars, resolved_style_chars (ps.name));
                write_tabs (x, ps.para);
                x.end ();
            }
            x.start ("CHARSTYLE").a ("CNAME", "Default Character Style").ai ("DefaultStyle", 1);
            write_char_attrs (x, bc, bc);
            x.end ();
            foreach (var cs in pub.styles.character) {
                x.start ("CHARSTYLE").a ("CNAME", cs.name);
                if (cs.based_on != "") x.a ("CPARENT", cs.based_on);
                var res = bc.clone ();
                res.apply (resolved_char_style (cs.name));
                write_char_attrs (x, cs.chars, res);
                x.end ();
            }
        }

        private void write_story (XmlOut x, Story st) {
            x.start ("StoryText");
            x.start ("DefaultStyle").end ();
            for (int i = 0; i < st.paras.size; i++) {
                var p = st.paras[i];
                var style_cf = resolved_style_chars (p.style);
                foreach (var r in p.runs) {
                    var res = style_cf.clone ();
                    if (r.cstyle != "") pub.styles.resolve_character (r.cstyle, res);
                    if (r.field != "") {
                        if (r.field == Fields.PAGE) x.start ("var").a ("name", "pgno").end ();
                        else if (r.field == Fields.PAGES) x.start ("var").a ("name", "pgco").end ();
                        else {
                            warn (_("Merge fields and other text variables are written as plain text."));
                            string label = Fields.label (r.field);
                            x.start ("ITEXT");
                            if (r.cstyle != "") x.a ("CPARENT", r.cstyle);
                            write_char_attrs (x, r.fmt, res);
                            x.a ("CH", label).end ();
                        }
                        continue;
                    }
                    write_run_text (x, r, res);
                }
                x.start (i < st.paras.size - 1 ? "para" : "trail");
                if (p.style != StyleSheet.BASIC) x.a ("PARENT", p.style);
                write_para_attrs (x, p.fmt);
                write_tabs (x, p.fmt);
                x.end ();
            }
            x.end ();
        }

        private void write_run_text (XmlOut x, Run r, CharFormat res) {
            var sb = new StringBuilder ();
            unichar c;
            int i = 0;
            while (r.text.get_next_char (ref i, out c)) {
                string? special = null;
                if (c == '\t') special = "tab";
                else if (c == 0x2028 || c == '\n') special = "breakline";
                else if (c == 0x00A0) special = "nbspace";
                else if (c == 0x2011) special = "nbhyphen";
                else if (c == 0x200B) special = "zwspace";
                else if (c == 0x2060 || c == 0xFEFF) special = "zwnbspace";
                else if (c == OBJ_CHAR) continue;
                if (special != null) {
                    flush_text (x, r, res, sb);
                    x.start (special);
                    if (r.cstyle != "") x.a ("CPARENT", r.cstyle);
                    write_char_attrs (x, r.fmt, res);
                    x.end ();
                    continue;
                }
                sb.append_unichar (c);
            }
            flush_text (x, r, res, sb);
        }

        private void flush_text (XmlOut x, Run r, CharFormat res, StringBuilder sb) {
            if (sb.len == 0) return;
            x.start ("ITEXT");
            if (r.cstyle != "") x.a ("CPARENT", r.cstyle);
            write_char_attrs (x, r.fmt, res);
            x.a ("CH", sb.str).end ();
            sb.truncate ();
        }

        private static string rect_path (double w, double h) {
            return "M0 0 L%s 0 L%s %s L0 %s L0 0 Z".printf (n (w), n (w), n (h), n (h));
        }

        private static string ellipse_path (double w, double h) {
            double rx = w / 2, ry = h / 2, kx = rx * KAPPA, ky = ry * KAPPA;
            var sb = new StringBuilder ();
            sb.append ("M%s %s ".printf (n (w), n (ry)));
            sb.append ("C%s %s %s %s %s %s ".printf (n (w), n (ry + ky), n (rx + kx), n (h), n (rx), n (h)));
            sb.append ("C%s %s %s %s %s %s ".printf (n (rx - kx), n (h), n (0), n (ry + ky), n (0), n (ry)));
            sb.append ("C%s %s %s %s %s %s ".printf (n (0), n (ry - ky), n (rx - kx), n (0), n (rx), n (0)));
            sb.append ("C%s %s %s %s %s %s Z".printf (n (rx + kx), n (0), n (w), n (ry - ky), n (w), n (ry)));
            return sb.str;
        }

        private static string rounded_path (double w, double h, double r) {
            r = double.min (r, double.min (w, h) / 2);
            double k = r * (1 - KAPPA);
            var sb = new StringBuilder ();
            sb.append ("M%s 0 L%s 0 ".printf (n (r), n (w - r)));
            sb.append ("C%s 0 %s %s %s %s ".printf (n (w - k), n (w), n (k), n (w), n (r)));
            sb.append ("L%s %s ".printf (n (w), n (h - r)));
            sb.append ("C%s %s %s %s %s %s ".printf (n (w), n (h - k), n (w - k), n (h), n (w - r), n (h)));
            sb.append ("L%s %s ".printf (n (r), n (h)));
            sb.append ("C%s %s 0 %s 0 %s ".printf (n (k), n (h), n (h - k), n (h - r)));
            sb.append ("L0 %s ".printf (n (r)));
            sb.append ("C0 %s %s 0 %s 0 Z".printf (n (k), n (k), n (r)));
            return sb.str;
        }

        private static string points_path (Gee.List<Point?> pts, bool closed) {
            var sb = new StringBuilder ();
            for (int i = 0; i < pts.size; i++) {
                sb.append ("%s%s %s ".printf (i == 0 ? "M" : "L", n (pts[i].x), n (pts[i].y)));
            }
            if (closed) sb.append ("Z");
            return sb.str.strip ();
        }

        private void geometry (XmlOut x, Item it, double ox, double oy) {
            double a = it.rotation * Math.PI / 180;
            double cx = it.x + it.w / 2, cy = it.y + it.h / 2;
            double xp = cx - (Math.cos (a) * it.w / 2 - Math.sin (a) * it.h / 2);
            double yp = cy - (Math.sin (a) * it.w / 2 + Math.cos (a) * it.h / 2);
            x.a ("XPOS", n (xp + ox)).a ("YPOS", n (yp + oy)).a ("WIDTH", n (it.w)).a ("HEIGHT", n (it.h)).a ("ROT", n (it.rotation));
            x.a ("gXpos", n (xp + ox)).a ("gYpos", n (yp + oy)).a ("gWidth", "0").a ("gHeight", "0");
        }

        private void common (XmlOut x, Item it, int own, int layer_index, string frame_path, int frtype) {
            x.ai ("ItemID", it.id).ai ("OwnPage", own).ai ("LAYER", layer_index);
            if (it.name != "") x.a ("ANNAME", it.name);
            x.ai ("LOCK", it.locked ? 1 : 0).ai ("PRINTABLE", it.nonprinting ? 0 : 1);
            if (it.flip_h) x.ai ("FLIPPEDH", 1);
            if (it.flip_v) x.ai ("FLIPPEDV", 1);
            x.ai ("FRTYPE", frtype).ai ("CLIPEDIT", frtype == 3 ? 1 : 0);
            x.a ("path", frame_path).a ("copath", frame_path);
            if (it.corner == CornerKind.ROUNDED && it.corner_radius > 0) x.a ("RADRECT", n (it.corner_radius));
            else if (it.corner != CornerKind.NONE && it.corner_radius > 0) warn (_("Bevel and inset corners are written as rounded corners."));
            var f = it.fill;
            if (f.kind == FillKind.LINEAR || f.kind == FillKind.RADIAL) {
                color_attr (x, "PCOLOR", "SHADE", f.stops.size > 0 ? f.stops[0].color : f.color);
                x.ai ("GRTYP", f.kind == FillKind.RADIAL ? 7 : 6);
                double ang = f.angle * Math.PI / 180;
                double dx = Math.cos (ang), dy = Math.sin (ang);
                double half = (Math.fabs (dx) * it.w + Math.fabs (dy) * it.h) / 2;
                if (f.kind == FillKind.RADIAL) {
                    x.a ("GRSTARTX", n (it.w / 2)).a ("GRSTARTY", n (it.h / 2)).a ("GRENDX", n (it.w)).a ("GRENDY", n (it.h / 2));
                } else {
                    x.a ("GRSTARTX", n (it.w / 2 - dx * half)).a ("GRSTARTY", n (it.h / 2 - dy * half)).a ("GRENDX", n (it.w / 2 + dx * half)).a ("GRENDY", n (it.h / 2 + dy * half));
                }
            } else if (f.kind == FillKind.SOLID) {
                color_attr (x, "PCOLOR", "SHADE", f.color);
            } else {
                x.a ("PCOLOR", "None").a ("SHADE", "100");
            }
            var s = it.stroke;
            if (s.visible ()) color_attr (x, "PCOLOR2", "SHADE2", s.color);
            else x.a ("PCOLOR2", "None").a ("SHADE2", "100");
            x.a ("PWIDTH", n (s.visible () ? s.width : 0));
            int art;
            switch (s.dash) {
                case DashKind.DASH: art = 2; break;
                case DashKind.DOT: art = 3; break;
                case DashKind.DASH_DOT: art = 4; break;
                default: art = 1; break;
            }
            x.ai ("PLINEART", art).ai ("PLINEEND", s.cap == 1 ? 32 : (s.cap == 2 ? 16 : 0)).ai ("PLINEJOIN", s.join == 1 ? 128 : (s.join == 2 ? 64 : 0));
            if (s.arrow_start > 0) x.ai ("startArrowIndex", 1);
            if (s.arrow_end > 0) x.ai ("endArrowIndex", 1);
            x.a ("TransValue", n (1 - it.opacity)).a ("TransValueS", n (1 - it.opacity));
            int flow = 0;
            if (it.wrap == WrapMode.BOUNDING_BOX) flow = 1;
            else if (it.wrap == WrapMode.CONTOUR) flow = 3;
            else if (it.wrap == WrapMode.JUMP) {
                flow = 1;
                warn (_("Jump object text wrap is written as bounding box wrap."));
            }
            x.ai ("TEXTFLOWMODE", flow);
            if (it.wrap != WrapMode.NONE) x.a ("WRAPOFFSET", n (it.wrap_offset));
            if (it.shadow.enabled) {
                x.ai ("HASSOFTSHADOW", 1).a ("SOFTSHADOWXOFFSET", n (it.shadow.dx)).a ("SOFTSHADOWYOFFSET", n (it.shadow.dy)).a ("SOFTSHADOWBLURRADIUS", n (it.shadow.blur));
                color_attr (x, "SOFTSHADOWCOLOR", "SOFTSHADOWSHADE", it.shadow.color);
                x.a ("SOFTSHADOWOPACITY", n (1 - it.shadow.opacity)).ai ("SOFTSHADOWBLENDMODE", 0);
            }
        }

        private void gradient_stops (XmlOut x, Item it) {
            var f = it.fill;
            if (f.kind != FillKind.LINEAR && f.kind != FillKind.RADIAL) return;
            foreach (var st in f.stops) {
                x.start ("CSTOP").a ("RAMP", n (st.offset));
                color_attr (x, "NAME", "SHADE", st.color);
                x.a ("TRANS", n (st.opacity)).end ();
            }
        }

        private string item_path (Item it, out int frtype) {
            frtype = 0;
            if (it.shape_ellipse) {
                frtype = 1;
                return ellipse_path (it.w, it.h);
            }
            if (it.corner == CornerKind.ROUNDED && it.corner_radius > 0 || (it.corner != CornerKind.NONE && it.corner_radius > 0)) {
                frtype = 2;
                return rounded_path (it.w, it.h, it.corner_radius);
            }
            return rect_path (it.w, it.h);
        }

        private void write_item (XmlOut x, string tag, Item it, int own, string master, double ox, double oy, Gee.HashMap<int, int> next, Gee.HashMap<int, int> back) {
            int li = pub.layer_index (it.layer);
            int frtype;
            switch (it.kind) {
                case ItemKind.TEXT:
                    var t = (TextFrame) it;
                    string path = item_path (it, out frtype);
                    x.start (tag).ai ("PTYPE", 4);
                    if (master != "") x.a ("OnMasterPage", master);
                    geometry (x, it, ox, oy);
                    common (x, it, own, li, path, frtype);
                    x.ai ("COLUMNS", t.columns).a ("COLGAP", n (t.gutter));
                    x.a ("EXTRA", n (t.inset_left)).a ("TEXTRA", n (t.inset_top)).a ("BEXTRA", n (t.inset_bottom)).a ("REXTRA", n (t.inset_right));
                    x.ai ("VAlign", t.valign.clamp (0, 2));
                    if (t.valign == 3) warn (_("Vertical justification is written as top alignment."));
                    x.ai ("NEXTITEM", next.has_key (t.id) ? next[t.id] : -1).ai ("BACKITEM", back.has_key (t.id) ? back[t.id] : -1);
                    gradient_stops (x, it);
                    if (!back.has_key (t.id) && pub.stories.has_key (t.story)) write_story (x, pub.stories[t.story]);
                    else {
                        x.start ("StoryText");
                        x.start ("DefaultStyle").end ();
                        x.end ();
                    }
                    x.end ();
                    break;
                case ItemKind.IMAGE:
                    var im = (ImageFrame) it;
                    string path = item_path (it, out frtype);
                    x.start (tag).ai ("PTYPE", 2);
                    if (master != "") x.a ("OnMasterPage", master);
                    geometry (x, it, ox, oy);
                    common (x, it, own, li, path, frtype);
                    write_image (x, im);
                    gradient_stops (x, it);
                    x.end ();
                    break;
                case ItemKind.SHAPE:
                    var s = (ShapeItem) it;
                    if (s.shape == ShapeKind.LINE) {
                        write_line (x, tag, s, own, master, li, ox, oy);
                        break;
                    }
                    string path;
                    int ptype = 6;
                    if (s.shape == ShapeKind.RECT) path = item_path (it, out frtype);
                    else if (s.shape == ShapeKind.ELLIPSE) {
                        frtype = 1;
                        path = ellipse_path (s.w, s.h);
                    } else {
                        frtype = 3;
                        path = points_path (s.local_points (), s.shape != ShapeKind.PATH || s.closed);
                        if (s.shape == ShapeKind.PATH && !s.closed) ptype = 7;
                    }
                    x.start (tag).ai ("PTYPE", ptype);
                    if (master != "") x.a ("OnMasterPage", master);
                    geometry (x, it, ox, oy);
                    common (x, it, own, li, path, frtype);
                    gradient_stops (x, it);
                    x.end ();
                    break;
                case ItemKind.TABLE:
                    write_table (x, tag, (TableItem) it, own, master, li, ox, oy);
                    break;
                case ItemKind.GROUP:
                    var g = (GroupItem) it;
                    if (g.rotation != 0) warn (_("Rotated groups are written without their rotation."));
                    x.start (tag).ai ("PTYPE", 12);
                    if (master != "") x.a ("OnMasterPage", master);
                    x.a ("XPOS", n (g.x + ox)).a ("YPOS", n (g.y + oy)).a ("WIDTH", n (g.w)).a ("HEIGHT", n (g.h)).a ("ROT", "0");
                    x.a ("gXpos", n (g.x + ox)).a ("gYpos", n (g.y + oy)).a ("gWidth", "0").a ("gHeight", "0");
                    x.a ("groupWidth", n (g.w)).a ("groupHeight", n (g.h));
                    var saved_rot = g.rotation;
                    g.rotation = 0;
                    common (x, it, own, li, rect_path (g.w, g.h), 0);
                    g.rotation = saved_rot;
                    foreach (var c in g.children) write_item (x, "PAGEOBJECT", c, own, "", -g.x, -g.y, next, back);
                    x.end ();
                    break;
            }
        }

        private void write_line (XmlOut x, string tag, ShapeItem s, int own, string master, int li, double ox, double oy) {
            var pts = s.local_points ();
            var a = s.to_page (pts[0].x, pts[0].y);
            var b = s.to_page (pts[1].x, pts[1].y);
            double len = Math.sqrt ((b.x - a.x) * (b.x - a.x) + (b.y - a.y) * (b.y - a.y));
            double ang = Math.atan2 (b.y - a.y, b.x - a.x) * 180 / Math.PI;
            x.start (tag).ai ("PTYPE", 5);
            if (master != "") x.a ("OnMasterPage", master);
            x.a ("XPOS", n (a.x + ox)).a ("YPOS", n (a.y + oy)).a ("WIDTH", n (len)).a ("HEIGHT", "1").a ("ROT", n (ang));
            x.a ("gXpos", n (a.x + ox)).a ("gYpos", n (a.y + oy)).a ("gWidth", "0").a ("gHeight", "0");
            var saved = s.fill;
            s.fill = new Fill ();
            common (x, s, own, li, "M0 0 L%s 0".printf (n (len)), 3);
            s.fill = saved;
            x.end ();
        }

        private void write_image (XmlOut x, ImageFrame im) {
            if (im.link != "") {
                string file = im.link;
                if (pub.base_dir != "" && file.has_prefix (pub.base_dir + "/")) file = file.substring (pub.base_dir.length + 1);
                x.a ("PFILE", file);
            } else if (im.media != "" && pub.media.has_key (im.media)) {
                try {
                    var bytes = pub.media[im.media].get_data ();
                    string ext = ImageStore.sniff (bytes);
                    if (ext == "") ext = "png";
                    x.ai ("isInlineImage", 1).a ("inlineImageExt", ext == "jpeg" ? "jpg" : ext);
                    x.a ("ImageData", Base64.encode (qt_compress (bytes)));
                    x.a ("PFILE", "");
                } catch (Error e) {
                    warn (_("An embedded image could not be written."));
                }
            } else {
                x.a ("PFILE", "");
            }
            if (im.merge_field != "") warn (_("Image merge fields are not written to Scribus files."));
            switch (im.fit) {
                case FitMode.MANUAL:
                    x.ai ("SCALETYPE", 1).ai ("RATIO", 1);
                    double sc = im.img_scale > 0 ? im.img_scale : 1;
                    x.a ("LOCALSCX", n (sc)).a ("LOCALSCY", n (sc)).a ("LOCALX", n (im.img_x / sc)).a ("LOCALY", n (im.img_y / sc));
                    break;
                case FitMode.STRETCH:
                    x.ai ("SCALETYPE", 0).ai ("RATIO", 0).a ("LOCALSCX", "1").a ("LOCALSCY", "1").a ("LOCALX", "0").a ("LOCALY", "0");
                    break;
                case FitMode.FILL:
                    var inf = ImageStore.get_default ().info (pub, im);
                    if (inf != null) {
                        var pl = ImageStore.place (im, inf);
                        double natural = 72.0 / (inf.dpi > 1 ? inf.dpi : 72);
                        double sc = pl.sx / natural;
                        x.ai ("SCALETYPE", 1).ai ("RATIO", 1).a ("LOCALSCX", n (sc)).a ("LOCALSCY", n (sc)).a ("LOCALX", n (pl.ox / sc)).a ("LOCALY", n (pl.oy / sc));
                    } else {
                        warn (_("Images set to fill their frame are written as fit to frame when the image cannot be read."));
                        x.ai ("SCALETYPE", 0).ai ("RATIO", 1).a ("LOCALSCX", "1").a ("LOCALSCY", "1").a ("LOCALX", "0").a ("LOCALY", "0");
                    }
                    break;
                default:
                    x.ai ("SCALETYPE", 0).ai ("RATIO", 1).a ("LOCALSCX", "1").a ("LOCALSCY", "1").a ("LOCALX", "0").a ("LOCALY", "0");
                    break;
            }
        }

        private void write_table (XmlOut x, string tag, TableItem t, int own, string master, int li, double ox, double oy) {
            x.start (tag).ai ("PTYPE", 16);
            if (master != "") x.a ("OnMasterPage", master);
            geometry (x, t, ox, oy);
            int frtype;
            common (x, t, own, li, item_path (t, out frtype), 0);
            x.ai ("Rows", t.rows).ai ("Columns", t.cols);
            var rh = new StringBuilder ();
            var rp = new StringBuilder ();
            double acc = 0;
            foreach (var v in t.row_h) {
                rh.append (n (v) + " ");
                rp.append (n (acc) + " ");
                acc += v;
            }
            var cw = new StringBuilder ();
            var cp = new StringBuilder ();
            acc = 0;
            foreach (var v in t.col_w) {
                cw.append (n (v) + " ");
                cp.append (n (acc) + " ");
                acc += v;
            }
            x.a ("RowHeights", rh.str.strip ()).a ("RowPositions", rp.str.strip ()).a ("ColumnWidths", cw.str.strip ()).a ("ColumnPositions", cp.str.strip ());
            x.start ("TableData");
            if (t.fill.kind == FillKind.SOLID) color_attr (x, "FillColor", "", t.fill.color);
            for (int r = 0; r < t.rows; r++) {
                for (int c = 0; c < t.cols; c++) {
                    var cell = t.cells[r][c];
                    if (cell.covered) continue;
                    x.start ("Cell").ai ("Row", r).ai ("Column", c).ai ("RowSpan", cell.row_span).ai ("ColumnSpan", cell.col_span);
                    string fill = cell.fill;
                    if (fill == ColorRef.NONE) {
                        if (r < t.header_rows && t.header_fill != ColorRef.NONE) fill = t.header_fill;
                        else if (r >= t.header_rows && (r - t.header_rows) % 2 == 1 && t.alt_fill != ColorRef.NONE) fill = t.alt_fill;
                    }
                    if (fill != ColorRef.NONE) color_attr (x, "FillColor", "FillShade", fill);
                    x.a ("LeftPadding", n (t.cell_inset)).a ("RightPadding", n (t.cell_inset)).a ("TopPadding", n (t.cell_inset)).a ("BottomPadding", n (t.cell_inset));
                    string bname;
                    double bshade;
                    resolve_color (t.border_color, out bname, out bshade);
                    foreach (string side in new string[] { "TopBorder", "BottomBorder", "LeftBorder", "RightBorder" }) {
                        x.start (side).start ("TableBorderLine").a ("Width", n (t.border_width)).ai ("PenStyle", 1).a ("Color", bname).a ("Shade", n (bshade)).end ().end ();
                    }
                    write_story (x, cell.story);
                    x.end ();
                }
            }
            x.end ();
            x.end ();
        }

        private string master_label (MasterPage m) {
            int count = 0;
            foreach (var o in pub.masters) if (o.name == m.name) count++;
            return count > 1 ? m.display_name () : m.name;
        }

        private void page_attrs (XmlOut x, double px, double py, int num, string nam, string mnam, bool left, Gee.ArrayList<Guide> guides, int page_index) {
            var s = pub.settings;
            x.a ("PAGEXPOS", n (px)).a ("PAGEYPOS", n (py)).a ("PAGEWIDTH", n (s.width)).a ("PAGEHEIGHT", n (s.height));
            x.a ("BORDERLEFT", n (s.margin_inside)).a ("BORDERRIGHT", n (s.margin_outside)).a ("BORDERTOP", n (s.margin_top)).a ("BORDERBOTTOM", n (s.margin_bottom));
            x.ai ("NUM", num).a ("NAM", nam).a ("MNAM", mnam).a ("Size", size_name ()).ai ("Orientation", s.landscape () ? 1 : 0).ai ("LEFT", left ? 1 : 0).ai ("PRESET", 0);
            x.ai ("AGhorizontalAutoGap", 0).ai ("AGhorizontalAutoCount", 0);
            if (s.columns > 1) x.a ("AGverticalAutoGap", n (s.gutter)).ai ("AGverticalAutoCount", s.columns).ai ("AGverticalAutoRefer", 1);
            else x.ai ("AGverticalAutoGap", 0).ai ("AGverticalAutoCount", 0);
            var v = new StringBuilder ();
            var h = new StringBuilder ();
            foreach (var g in guides) {
                if (g.vertical) v.append (n (g.pos) + " ");
                else h.append (n (g.pos) + " ");
            }
            x.a ("VerticalGuides", v.str).a ("HorizontalGuides", h.str);
        }

        private string size_name () {
            var p = PageSize.match (pub.settings.width, pub.settings.height);
            if (p == null) return "Custom";
            switch (p.id) {
                case "a3": return "A3";
                case "a4": return "A4";
                case "a5": return "A5";
                case "a6": return "A6";
                case "b5": return "B5";
                case "letter": return "Letter";
                case "legal": return "Legal";
                case "tabloid": return "Tabloid";
                default: return "Custom";
            }
        }

        private static string section_type (NumberStyle s) {
            switch (s) {
                case NumberStyle.ROMAN_LOWER: return "Type_i_ii_iii";
                case NumberStyle.ROMAN_UPPER: return "Type_I_II_III";
                case NumberStyle.ALPHA_LOWER: return "Type_a_b_c";
                case NumberStyle.ALPHA_UPPER: return "Type_A_B_C";
                default: return "Type_1_2_3";
            }
        }

        public string write () throws Error {
            adhoc.clear ();
            adhoc_order.clear ();
            var s = pub.settings;
            var next = new Gee.HashMap<int, int> ();
            var back = new Gee.HashMap<int, int> ();
            foreach (var st in pub.stories.values) {
                var frames = pub.thread_frames (st.id);
                for (int i = 0; i + 1 < frames.size; i++) {
                    next[frames[i].id] = frames[i + 1].id;
                    back[frames[i + 1].id] = frames[i].id;
                }
            }
            var body = new XmlOut (false);
            write_styles (body);
            for (int i = 0; i < pub.layers.size; i++) {
                var l = pub.layers[i];
                body.start ("LAYERS").ai ("NUMMER", i).ai ("LEVEL", i).a ("NAME", l.name).ai ("SICHTBAR", l.visible ? 1 : 0).ai ("DRUCKEN", l.printable ? 1 : 0).ai ("EDIT", l.locked ? 0 : 1);
                body.ai ("SELECT", 0).ai ("FLOW", 1).a ("TRANS", "1").ai ("BLEND", 0).ai ("OUTL", 0).a ("LAYERC", l.color).end ();
            }
            body.start ("PageSets");
            body.start ("Set").a ("Name", "Single Page").ai ("FirstPage", 0).ai ("Rows", 1).ai ("Columns", 1).end ();
            body.start ("Set").a ("Name", "Facing Pages").ai ("FirstPage", 1).ai ("Rows", 1).ai ("Columns", 2).end ();
            body.end ();
            body.start ("Sections");
            var secs = new Gee.ArrayList<Section> ();
            secs.add_all (pub.sections);
            secs.sort ((a, b) => a.start_page - b.start_page);
            for (int i = 0; i < secs.size; i++) {
                int to = i + 1 < secs.size ? secs[i + 1].start_page - 1 : pub.pages.size - 1;
                body.start ("Section").ai ("Number", i).a ("Name", secs[i].name != "" ? secs[i].name : i.to_string ()).ai ("From", secs[i].start_page).ai ("To", int.max (secs[i].start_page, to));
                body.a ("Type", section_type (secs[i].style)).ai ("Start", secs[i].start_number).ai ("Reversed", 0).ai ("Active", 1).a ("FillChar", "0").ai ("FieldWidth", 0).end ();
                if (secs[i].prefix != "") warn (_("Section prefixes are not written to Scribus files."));
            }
            body.end ();
            var master_entries = new Gee.ArrayList<string> ();
            var master_of = new Gee.HashMap<string, MasterPage> ();
            var master_is_left = new Gee.HashMap<string, bool> ();
            foreach (var m in pub.masters) {
                if (m.based_on != "") warn (_("Master pages based on other masters are written with the parent items copied in."));
                string label = master_label (m);
                if (s.facing && m.left_items.size > 0) {
                    master_entries.add (label + " Left");
                    master_of[label + " Left"] = m;
                    master_is_left[label + " Left"] = true;
                    master_entries.add (label + " Right");
                    master_of[label + " Right"] = m;
                    master_is_left[label + " Right"] = false;
                } else {
                    master_entries.add (label);
                    master_of[label] = m;
                    master_is_left[label] = false;
                }
            }
            for (int i = 0; i < master_entries.size; i++) {
                string name = master_entries[i];
                body.start ("MASTERPAGE");
                page_attrs (body, ORIGIN_X, ORIGIN_Y, i, name, "", master_is_left[name], master_of[name].guides, -1);
                body.end ();
            }
            var px = new double[pub.pages.size];
            var py = new double[pub.pages.size];
            if (s.facing) {
                var spreads = pub.spreads ();
                for (int si = 0; si < spreads.size; si++) {
                    foreach (int pi in spreads[si].pages) {
                        bool left = pub.is_left_page (pi);
                        px[pi] = ORIGIN_X + (left ? 0 : s.width);
                        py[pi] = ORIGIN_Y + si * (s.height + GAP);
                    }
                }
            } else {
                for (int i = 0; i < pub.pages.size; i++) {
                    px[i] = ORIGIN_X;
                    py[i] = ORIGIN_Y + i * (s.height + GAP);
                }
            }
            for (int i = 0; i < pub.pages.size; i++) {
                var pg = pub.pages[i];
                string mnam = "";
                var m = pub.master (pg.master);
                if (m != null && !pg.hide_master) {
                    string label = master_label (m);
                    if (s.facing && m.left_items.size > 0) mnam = label + (pub.is_left_page (i) ? " Left" : " Right");
                    else mnam = label;
                } else if (pg.hide_master || pg.master == "") {
                    mnam = "";
                }
                if (pg.overridden.size > 0) warn (_("Overridden master items are written as page items only."));
                body.start ("PAGE");
                page_attrs (body, px[i], py[i], i, "", mnam, pub.is_left_page (i), pg.guides, i);
                body.end ();
            }
            for (int i = 0; i < master_entries.size; i++) {
                string name = master_entries[i];
                var m = master_of[name];
                bool left = master_is_left[name];
                var items = new Gee.ArrayList<Item> ();
                foreach (var parent in pub.master_chain (m.id)) items.add_all (parent.items_for (left));
                foreach (var it in items) write_item (body, "MASTEROBJECT", it, i, name, ORIGIN_X, ORIGIN_Y, next, back);
            }
            for (int i = 0; i < pub.pages.size; i++) {
                foreach (var it in pub.pages[i].items) write_item (body, "PAGEOBJECT", it, i, "", px[i], py[i], next, back);
            }
            string body_xml = body.finish ();

            var x = new XmlOut ();
            x.start ("SCRIBUSUTF8NEW").a ("Version", "1.5.8");
            x.start ("DOCUMENT").ai ("ANZPAGES", pub.pages.size).a ("PAGEWIDTH", n (s.width)).a ("PAGEHEIGHT", n (s.height));
            x.a ("BORDERLEFT", n (s.margin_inside)).a ("BORDERRIGHT", n (s.margin_outside)).a ("BORDERTOP", n (s.margin_top)).a ("BORDERBOTTOM", n (s.margin_bottom));
            x.ai ("PRESET", 0).a ("BleedTop", n (s.bleed_top)).a ("BleedLeft", n (s.bleed_inside)).a ("BleedRight", n (s.bleed_outside)).a ("BleedBottom", n (s.bleed_bottom));
            x.ai ("ORIENTATION", s.landscape () ? 1 : 0).a ("PAGESIZE", size_name ()).ai ("FIRSTNUM", 1).ai ("BOOK", s.facing ? 1 : 0).ai ("FIRSTLEFT", s.start_left ? 1 : 0);
            string[] unit_names = { "pt", "mm", "in", "pc", "cm" };
            int unit = 0;
            for (int i = 0; i < unit_names.length; i++) if (unit_names[i] == s.units) unit = i;
            x.ai ("UNITS", unit);
            var basic = resolved_style_chars (StyleSheet.BASIC);
            x.a ("DFONT", font_name (basic.font ?? "Inter", basic.bold == 1, basic.italic == 1)).a ("DSIZE", n (basic.size)).ai ("DCOL", 1).a ("DGAP", "0");
            x.a ("TITLE", pub.meta.title).a ("AUTHOR", pub.meta.author).a ("SUBJECT", pub.meta.subject).a ("KEYWORDS", pub.meta.keywords).a ("COMMENTS", "").a ("PUBLISHER", "").a ("DOCDATE", pub.meta.created);
            x.a ("BaseGridSpace", n (s.baseline_step)).a ("BaseGridOffset", n (s.baseline_start));
            x.a ("ScratchLeft", "100").a ("ScratchRight", "100").a ("ScratchTop", "20").a ("ScratchBottom", "20").a ("GapHorizontal", "0").a ("GapVertical", n (GAP));
            x.ai ("AUTOSPALTEN", 1).a ("ABSTSPALTEN", "11").ai ("ALAYER", 0).a ("LANGUAGE", "en_US").ai ("AUTOMATIC", 1).ai ("AUTOCHECK", 0);
            foreach (var sw in pub.swatches) {
                x.start ("COLOR").a ("NAME", sw.name);
                if (sw.model == ColorModel.CMYK) {
                    x.a ("SPACE", "CMYK").a ("C", n (sw.c * 100)).a ("M", n (sw.m * 100)).a ("Y", n (sw.y * 100)).a ("K", n (sw.k * 100));
                } else {
                    x.a ("SPACE", "RGB").a ("R", n (sw.r * 255)).a ("G", n (sw.g * 255)).a ("B", n (sw.b * 255));
                }
                if (sw.spot) x.ai ("Spot", 1);
                if (sw.name == "Registration") x.ai ("Register", 1);
                x.end ();
            }
            foreach (string key in adhoc_order) {
                x.start ("COLOR").a ("NAME", adhoc[key]);
                if (key.has_prefix ("cmyk:")) {
                    string[] f = key.substring (5).split (",");
                    double[] v = { 0, 0, 0, 0 };
                    for (int i = 0; i < 4 && i < f.length; i++) v[i] = Units.parse_num (f[i], 0);
                    x.a ("SPACE", "CMYK").a ("C", n (v[0] * 100)).a ("M", n (v[1] * 100)).a ("Y", n (v[2] * 100)).a ("K", n (v[3] * 100));
                } else {
                    var c = pub.resolve (key);
                    x.a ("SPACE", "RGB").a ("R", n (Math.round (c.r * 255))).a ("G", n (Math.round (c.g * 255))).a ("B", n (Math.round (c.b * 255)));
                }
                x.end ();
            }
            x.raw (body_xml);
            x.end ();
            x.end ();
            return x.finish ();
        }
    }
}
