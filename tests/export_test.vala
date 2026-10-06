using Singularity.Apps.Publish;

string outdir () {
    string d = Path.build_filename (Environment.get_tmp_dir (), "publish-export-%lld".printf (get_monotonic_time ()));
    DirUtils.create_with_parents (d, 0700);
    return d;
}

bool has_tool (string name) {
    return Environment.find_program_in_path (name) != null;
}

string run (string[] argv) {
    string o, e;
    int st;
    try {
        Process.spawn_sync (null, argv, null, SpawnFlags.SEARCH_PATH, null, out o, out e, out st);
    } catch (Error err) {
        return "";
    }
    return o + e;
}

uint8[] png_bytes (double r, double g, double b) {
    var s = new Cairo.ImageSurface (Cairo.Format.RGB24, 20, 20);
    var cr = new Cairo.Context (s);
    cr.set_source_rgb (r, g, b);
    cr.paint ();
    return XpsExport.surface_png (s);
}

Publication sample () {
    var s = new DocSettings ();
    s.width = 300;
    s.height = 200;
    s.set_margins (20);
    var p = Publication.create (s, 2);
    p.meta.title = "Export Sample";
    p.styles.find_paragraph (StyleSheet.BASIC).chars.font = "DejaVu Sans";
    var t = p.add_text_frame (p.pages[0].items, 20, 20, 200, 75);
    t.name = "Headline Frame";
    var st = p.story (t.story);
    st.paras.clear ();
    var p1 = new Paragraph.with_text ("Grand Opening", "Heading 1");
    p1.fmt.leading = 22;
    p1.runs[0].fmt.size = 18;
    st.paras.add (p1);
    var p2 = new Paragraph.with_text ("Visit ", "Body Text");
    var link = new Run ("our site");
    link.fmt.link = "https://example.org/shop";
    link.fmt.bold = 1;
    p2.runs.add (link);
    p2.runs.add (new Run (" today & save."));
    st.paras.add (p2);
    var r = new ShapeItem (ShapeKind.RECT);
    r.id = p.next_id ();
    r.layer = p.layers[0].id;
    r.x = 230;
    r.y = 20;
    r.w = 50;
    r.h = 50;
    r.fill = new Fill.solid ("#ff0000");
    r.alt_text = "Red square";
    r.link = "page:1";
    p.pages[0].items.add (r);
    var im = new ImageFrame ();
    im.id = p.next_id ();
    im.layer = p.layers[0].id;
    im.x = 20;
    im.y = 100;
    im.w = 80;
    im.h = 60;
    im.media = p.add_media (png_bytes (0, 0.5, 1), "blue.png");
    im.alt_text = "Blue picture";
    p.pages[0].items.add (im);
    var wa = new WordArtItem ();
    wa.id = p.next_id ();
    wa.layer = p.layers[0].id;
    wa.text = "Wow";
    wa.x = 120;
    wa.y = 100;
    wa.w = 100;
    wa.h = 50;
    wa.fill = new Fill.solid ("#008000");
    p.pages[0].items.add (wa);
    var t2 = p.add_text_frame (p.pages[1].items, 20, 20, 200, 40);
    p.story (t2.story).insert_text (TextPos (0, 0), "Second page");
    p.bookmarks.add (new Bookmark ("Second", 1, 20, 20));
    return p;
}

Gdk.Pixbuf load (string path) {
    try {
        return new Gdk.Pixbuf.from_file (path);
    } catch (Error e) {
        warning ("%s: %s", path, e.message);
        assert_not_reached ();
    }
}

uint8[] rgb_at (Gdk.Pixbuf pb, int x, int y) {
    unowned uint8[] d = pb.get_pixels_with_length ();
    int i = y * pb.rowstride + x * pb.n_channels;
    return { d[i], d[i + 1], d[i + 2] };
}

void test_images () {
    var p = sample ();
    var o = new ExportOptions ();
    o.dpi = 72;
    o.bleed = false;
    o.ranges = "1";
    string dir = outdir ();
    try {
        foreach (string fmt in new string[] { "tiff", "gif", "bmp" }) {
            var ex = new Exporter (p, o);
            var files = ex.export_images (dir, "page", fmt);
            assert (files.size == 1);
            var pb = load (files[0]);
            assert (pb.width == 300 && pb.height == 200);
            var red = rgb_at (pb, 255, 45);
            assert (red[0] > 200 && red[1] < 60 && red[2] < 60);
            var white = rgb_at (pb, 290, 190);
            assert (white[0] > 230 && white[1] > 230 && white[2] > 230);
            var blue = rgb_at (pb, 60, 130);
            assert (blue[2] > 180 && blue[0] < 60);
        }
        o.image_cmyk = true;
        var files = new Exporter (p, o).export_images (dir, "cmyk", "tiff");
        uint8[] data;
        FileUtils.get_data (files[0], out data);
        assert (data[0] == 'I' && data[1] == 'I' && data[2] == 42);
        uint32 ifd = (uint32) data[4] | ((uint32) data[5] << 8) | ((uint32) data[6] << 16) | ((uint32) data[7] << 24);
        int n = (int) data[ifd] | ((int) data[ifd + 1] << 8);
        bool separated = false, four = false;
        for (int i = 0; i < n; i++) {
            int e = (int) ifd + 2 + i * 12;
            int tag = (int) data[e] | ((int) data[e + 1] << 8);
            int val = (int) data[e + 8] | ((int) data[e + 9] << 8);
            if (tag == 262 && val == 5) separated = true;
            if (tag == 277 && val == 4) four = true;
        }
        assert (separated && four);
        if (has_tool ("tiffinfo")) {
            string info = run ({ "tiffinfo", files[0] });
            assert (info.contains ("separated") || info.contains ("CMYK"));
        }
        o.image_cmyk = false;
        o.transparent = true;
        files = new Exporter (p, o).export_images (dir, "alpha", "gif");
        var pb = load (files[0]);
        assert (pb.has_alpha);
        unowned uint8[] d = pb.get_pixels_with_length ();
        assert (d[190 * pb.rowstride + 290 * 4 + 3] == 0);
    } catch (Error e) {
        warning ("%s", e.message);
        assert_not_reached ();
    }
}

void test_gif_many_colors () {
    var s = new Cairo.ImageSurface (Cairo.Format.RGB24, 256, 64);
    var cr = new Cairo.Context (s);
    var g = new Cairo.Pattern.linear (0, 0, 256, 0);
    g.add_color_stop_rgb (0, 1, 0, 0);
    g.add_color_stop_rgb (0.5, 0, 1, 0);
    g.add_color_stop_rgb (1, 0, 0, 1);
    cr.set_source (g);
    cr.paint ();
    s.flush ();
    var data = GifWriter.encode (RasterPixels.from_surface (s, false), false);
    string path = Path.build_filename (outdir (), "grad.gif");
    try {
        FileUtils.set_data (path, data);
    } catch (Error e) {
        assert_not_reached ();
    }
    var pb = load (path);
    for (int x = 0; x < 256; x += 17) {
        var src = RasterPixels.from_surface (s, false);
        var got = rgb_at (pb, x, 30);
        int i = (30 * 256 + x) * 3;
        for (int k = 0; k < 3; k++) assert (((int) got[k] - (int) src.data[i + k]).abs () < 40);
    }
}

void test_html () {
    var p = sample ();
    string dir = outdir ();
    string path = Path.build_filename (dir, "site.html");
    try {
        HtmlExport.export (p, path);
        string html;
        FileUtils.get_contents (path, out html);
        assert (html.has_prefix ("<!DOCTYPE html>"));
        assert (html.contains ("<title>Export Sample</title>"));
        assert (html.contains ("Grand Opening"));
        assert (html.contains ("href=\"https://example.org/shop\""));
        assert (html.contains ("today &amp; save."));
        assert (html.contains ("id=\"page-1\"") && html.contains ("id=\"page-2\""));
        assert (html.contains ("href=\"#page-2\""));
        assert (html.contains ("alt=\"Blue picture\""));
        assert (html.contains ("alt=\"Wow\""));
        assert (html.contains ("aria-label=\"Red square\""));
        assert (html.contains ("id=\"bm-Second\""));
        var files = new Gee.ArrayList<string> ();
        var d = Dir.open (Path.build_filename (dir, "site_files"));
        string? n;
        while ((n = d.read_name ()) != null) files.add (n);
        assert (files.size >= 2);
        foreach (string f in files) assert (html.contains ("site_files/" + f));
    } catch (Error e) {
        warning ("%s", e.message);
        assert_not_reached ();
    }
}

void test_xps () {
    var p = sample ();
    string path = Path.build_filename (outdir (), "doc.xps");
    try {
        var o = new ExportOptions ();
        o.dpi = 96;
        o.bleed = false;
        assert (XpsExport.export (p, o, path) == 2);
        uint8[] data;
        FileUtils.get_data (path, out data);
        var zip = new ZipReader (data);
        foreach (string part in new string[] { "[Content_Types].xml", "_rels/.rels", "FixedDocSeq.fdseq", "Documents/1/FixedDoc.fdoc", "Documents/1/Pages/1.fpage", "Documents/1/Pages/2.fpage", "Documents/1/Pages/_rels/1.fpage.rels" }) assert (zip.has (part));
        string? font_part = null;
        foreach (string name in zip.names ()) if (name.has_prefix ("Resources/Fonts/") && name.has_suffix (".odttf")) font_part = name;
        assert (font_part != null);
        string guid = Path.get_basename (font_part).replace (".odttf", "");
        var clear = XpsResources.obfuscate (zip.read (font_part), guid);
        assert ((clear[0] == 0 && clear[1] == 1 && clear[2] == 0 && clear[3] == 0) || (clear[0] == 'O' && clear[1] == 'T') || (clear[0] == 't' && clear[1] == 't'));
        assert (zip.read_text ("[Content_Types].xml").contains ("application/vnd.ms-package.obfuscated-opentype"));
        assert (zip.read_text ("Documents/1/Pages/_rels/1.fpage.rels").contains ("/" + font_part));
        foreach (string part in new string[] { "[Content_Types].xml", "FixedDocSeq.fdseq", "Documents/1/FixedDoc.fdoc", "Documents/1/Pages/1.fpage" }) {
            Xml.Doc* doc = XmlIn.parse (zip.read_text (part));
            assert (doc != null);
            delete doc;
        }
        string page = zip.read_text ("Documents/1/Pages/1.fpage");
        assert (page.contains ("Width=\"400\" Height=\"266.667\""));
        assert (page.contains ("FixedPage.NavigateUri=\"https://example.org/shop\""));
        assert (page.contains ("FixedPage.NavigateUri=\"../FixedDoc.fdoc#page2\""));
        assert (page.contains ("<Glyphs ") && page.contains ("UnicodeString=\"Grand Opening\""));
        assert (page.contains ("Fill=\"#FFFF0000\""));
        assert (!page.contains ("Resources/Images/1.png\" Viewbox=\"0,0,400"));
        if (has_tool ("mutool")) {
            string png = Path.build_filename (outdir (), "xps-%d.png");
            run ({ "mutool", "draw", "-o", png, "-r", "72", path, "1" });
            string first = png.replace ("%d", "1");
            assert (FileUtils.test (first, FileTest.EXISTS));
            var pb = load (first);
            assert ((pb.width - 300).abs () <= 2);
            var red = rgb_at (pb, 255, 45);
            assert (red[0] > 200 && red[1] < 80);
            string txt = run ({ "mutool", "draw", "-F", "txt", "-o", "-", path, "1" });
            assert (txt.contains ("Grand Opening"));
            assert (txt.contains ("Visit our site today & save."));
        } else {
            print ("mutool missing, XPS render check skipped\n");
        }
    } catch (Error e) {
        warning ("%s", e.message);
        assert_not_reached ();
    }
}

void test_docx () {
    var p = sample ();
    string path = Path.build_filename (outdir (), "doc.docx");
    try {
        DocxWriter.export (p, path);
        uint8[] data;
        FileUtils.get_data (path, out data);
        var zip = new ZipReader (data);
        foreach (string part in new string[] { "[Content_Types].xml", "_rels/.rels", "word/document.xml", "word/styles.xml", "word/_rels/document.xml.rels", "docProps/core.xml" }) {
            assert (zip.has (part));
            Xml.Doc* doc = XmlIn.parse (zip.read_text (part));
            assert (doc != null);
            delete doc;
        }
        string doc = zip.read_text ("word/document.xml");
        assert (doc.contains ("Grand Opening") && doc.contains ("Second page"));
        assert (doc.contains ("<w:br w:type=\"page\"/>"));
        assert (doc.contains ("descr=\"Blue picture\""));
        assert (doc.contains ("w:anchor=\"page-2\"") || doc.contains ("page-2"));
        assert (doc.contains ("<wp:posOffset>254000</wp:posOffset>"));
        string rels = zip.read_text ("word/_rels/document.xml.rels");
        assert (rels.contains ("https://example.org/shop") && rels.contains ("media/image1."));
        string styles = zip.read_text ("word/styles.xml");
        assert (styles.contains ("w:styleId=\"Heading1\"") && styles.contains ("<w:name w:val=\"Heading 1\"/>"));
        var back = TextImport.read (path);
        bool found = false;
        foreach (var para in back.paragraphs) if (para.text ().contains ("Grand Opening")) found = true;
        assert (found);
        assert (back.styles.find_paragraph ("Heading 1") != null);
    } catch (Error e) {
        warning ("%s", e.message);
        assert_not_reached ();
    }
}

void test_odg () {
    var p = sample ();
    string path = Path.build_filename (outdir (), "doc.odg");
    try {
        OdgWriter.export (p, path);
        uint8[] data;
        FileUtils.get_data (path, out data);
        var head = new StringBuilder ();
        for (int i = 30; i < 38; i++) head.append_c ((char) data[i]);
        assert (head.str == "mimetype");
        var zip = new ZipReader (data);
        assert (zip.read_text ("mimetype") == "application/vnd.oasis.opendocument.graphics");
        foreach (string part in new string[] { "content.xml", "styles.xml", "meta.xml", "META-INF/manifest.xml" }) {
            Xml.Doc* doc = XmlIn.parse (zip.read_text (part));
            assert (doc != null);
            delete doc;
        }
        string content = zip.read_text ("content.xml");
        assert (content.contains ("<draw:page") && content.contains ("Grand Opening") && content.contains ("Second page"));
        assert (content.contains ("xlink:href=\"https://example.org/shop\""));
        assert (content.contains ("<svg:desc>Blue picture</svg:desc>"));
        assert (content.contains ("draw:fill-color=\"#ff0000\""));
        string man = zip.read_text ("META-INF/manifest.xml");
        foreach (string n in zip.names ()) if (n.has_prefix ("Pictures/")) assert (man.contains (n));
        string styles = zip.read_text ("styles.xml");
        assert (styles.contains ("fo:page-width=\"10.5833cm\""));
    } catch (Error e) {
        warning ("%s", e.message);
        assert_not_reached ();
    }
}

void test_idml_roundtrip () {
    var p = sample ();
    p.swatches.add (new Swatch.cmyk ("Brand Orange", 0, 0.55, 1, 0, true));
    var sh = new ShapeItem (ShapeKind.ELLIPSE);
    sh.id = p.next_id ();
    sh.layer = p.layers[0].id;
    sh.x = 150;
    sh.y = 150;
    sh.w = 40;
    sh.h = 30;
    sh.rotation = 30;
    sh.fill = new Fill.solid (ColorRef.swatch ("Brand Orange"));
    p.pages[1].items.add (sh);
    try {
        var data = new IdmlWriter (p).write ();
        string path = Path.build_filename (outdir (), "doc.idml");
        FileUtils.set_data (path, data);
        var reader = new IdmlReader ();
        var q = reader.read (data);
        assert (q.pages.size == 2);
        assert (Math.fabs (q.settings.width - 300) < 0.01 && Math.fabs (q.settings.height - 200) < 0.01);
        TextFrame? head = null;
        foreach (var it in q.pages[0].items) {
            var t = it as TextFrame;
            if (t != null && q.story (t.story).plain_text ().contains ("Grand Opening")) head = t;
        }
        assert (head != null);
        assert (Math.fabs (head.x - 20) < 0.5 && Math.fabs (head.y - 20) < 0.5 && Math.fabs (head.w - 200) < 0.5 && Math.fabs (head.h - 75) < 0.5);
        var hs = q.story (head.story);
        assert (hs.paras[0].style == "Heading 1");
        assert (hs.plain_text ().contains ("our site today & save."));
        var sw = q.swatch ("Brand Orange");
        assert (sw != null && sw.spot && Math.fabs (sw.m - 0.55) < 0.01);
        ShapeItem? ell = null;
        foreach (var it in q.pages[1].items) if (it is ShapeItem) ell = (ShapeItem) it;
        assert (ell != null && Math.fabs (ell.rotation - 30) < 0.5 || Math.fabs (ell.rotation + 330) < 0.5 || Math.fabs (ell.rotation - 30) < 0.5);
        var c = ell.center ();
        assert (Math.fabs (c.x - 170) < 1 && Math.fabs (c.y - 165) < 1);
        bool image = false;
        foreach (var it in q.pages[0].items) if (it is ImageFrame && ((ImageFrame) it).has_image ()) image = true;
        assert (image);
        assert (q.styles.find_paragraph ("Heading 1") != null);
    } catch (Error e) {
        warning ("%s", e.message);
        assert_not_reached ();
    }
}

string bytes_text (uint8[] d) {
    var sb = new StringBuilder.sized (d.length + 1);
    sb.append_len ((string) d, d.length);
    return sb.str;
}

void test_email () {
    var p = sample ();
    var t = new DataTable ();
    t.fields.add ("Name");
    t.fields.add ("Email");
    t.records.add (new Gee.ArrayList<string>.wrap ({ "Zoe", "zoe@example.org" }));
    t.records.add (new Gee.ArrayList<string>.wrap ({ "Bárbara", "barbara@example.org" }));
    t.records.add (new Gee.ArrayList<string>.wrap ({ "Nobody", "" }));
    t.records.add (new Gee.ArrayList<string>.wrap ({ "Ann", "ann@example.org" }));
    Merge.set_source (p, t, "csv", "");
    var f = p.add_text_frame (p.pages[0].items, 20, 170, 200, 20);
    p.story (f.story).insert_field (TextPos (0, 0), Fields.merge ("Name"));
    p.merge.email_field = "Email";
    p.merge.email_subject = "Hello «Name»";
    p.merge.sorts.add (new MergeSort ("Name"));
    p.merge.excluded.add (3);
    p.business.set ("email", "shop@example.org");
    p.business.set ("organization", "Shop");
    try {
        var list = EmailMerge.write_messages (p, outdir (), true);
        assert (list.size == 2);
        assert (list[0].to == "barbara@example.org" && list[1].to == "zoe@example.org");
        string msg = bytes_text (list[0].data);
        assert (msg.contains ("To: barbara@example.org\r\n"));
        assert (msg.contains ("Subject: =?UTF-8?B?"));
        assert (msg.contains ("From: Shop <shop@example.org>"));
        assert (msg.contains ("Content-Type: multipart/mixed;"));
        assert (msg.contains ("Content-Type: text/html; charset=utf-8"));
        assert (msg.contains ("Content-Type: application/pdf;"));
        assert (msg.contains ("Content-ID: <asset-"));
        foreach (string line in msg.split ("\r\n")) assert (line.length <= 998);
        string html_part = msg.substring (msg.index_of ("text/html"));
        assert (html_part.contains ("B=C3=A1rbara") || html_part.contains ("Bárbara"));
        string subj_b64 = msg.substring (msg.index_of ("=?UTF-8?B?") + 10);
        subj_b64 = subj_b64.substring (0, subj_b64.index_of ("?="));
        var dec = Base64.decode (subj_b64);
        var subj = new StringBuilder ();
        foreach (uint8 b in dec) subj.append_c ((char) b);
        assert (subj.str == "Hello Bárbara");
        var one = EmailMerge.message_for_page (p, 0, "Flyer", "x@example.org", false, outdir ());
        assert (bytes_text (one.data).contains ("To: x@example.org"));
    } catch (Error e) {
        warning ("%s", e.message);
        assert_not_reached ();
    }
}

void main (string[] args) {
    Test.init (ref args);
    Test.add_func ("/export/images", test_images);
    Test.add_func ("/export/gif-colors", test_gif_many_colors);
    Test.add_func ("/export/html", test_html);
    Test.add_func ("/export/xps", test_xps);
    Test.add_func ("/export/docx", test_docx);
    Test.add_func ("/export/odg", test_odg);
    Test.add_func ("/export/idml-roundtrip", test_idml_roundtrip);
    Test.add_func ("/export/email", test_email);
    Test.run ();
}
