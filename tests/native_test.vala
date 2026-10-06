using Singularity.Apps.Publish;

Publication rich () {
    var p = Publication.create (null, 3);
    p.settings.facing = true;
    p.settings.set_bleed (8.5);
    p.settings.columns = 3;
    p.settings.gutter = 14;
    p.settings.units = "in";
    p.settings.impose = "nup:2x5:a4";
    p.meta.title = "Round Trip & <Test>";
    p.meta.author = "Ada";
    var l2 = new Layer (p.next_id (), "Artwork");
    l2.locked = true;
    l2.printable = false;
    l2.color = "#ff0000";
    p.layers.add (l2);
    p.swatches.add (new Swatch.cmyk ("Pantone 185", 0, 0.91, 0.76, 0, true));
    p.swatches.add (new Swatch.rgb ("Web", 0.1, 0.2, 0.3));
    var ps = new ParagraphStyle ("Intro", "Body Text");
    ps.para.drop_lines = 2;
    ps.para.tabs = TabStop.serialize (new Gee.ArrayList<TabStop>.wrap ({ new TabStop (100, TabKind.RIGHT, ".") }));
    ps.chars.color = ColorRef.swatch ("Pantone 185", 60);
    ps.next = "Body Text";
    p.styles.paragraph.add (ps);
    var cs = new CharacterStyle ("Accent", "Strong");
    cs.chars.features = "smcp=1";
    p.styles.character.add (cs);
    var sec = new Section (2);
    sec.prefix = "B-";
    sec.style = NumberStyle.ROMAN_UPPER;
    sec.name = "Back";
    p.sections.add (sec);
    var m = p.master ("A");
    m.guides.add (new Guide (true, 20.5));
    var mf = p.add_text_frame (m.left_items, 10, 10, 50, 20);
    p.story (mf.story).insert_field (TextPos (0, 0), Fields.PAGE);
    var mb = new MasterPage ("B", "Chapter");
    mb.based_on = "A";
    p.masters.add (mb);
    p.pages[1].master = "B";
    p.pages[2].hide_master = true;
    p.pages[0].guides.add (new Guide (false, 300));
    var f1 = p.add_text_frame (p.pages[0].items, 36, 36, 200, 300);
    var f2 = p.add_text_frame (p.pages[1].items, 36, 36, 200, 300);
    p.link_frames (f1, f2);
    f1.columns = 2;
    f1.inset_left = 4;
    f1.valign = 1;
    f1.auto_height = false;
    f1.fill = new Fill.solid (ColorRef.swatch ("Web"));
    f1.stroke = new Stroke.with (ColorRef.BLACK, 0.5);
    f1.stroke.dash = DashKind.DOT;
    var st = p.story (f1.story);
    st.paras.clear ();
    var para = new Paragraph.with_text ("Tab\tseparated  spaces ", "Intro");
    para.fmt.align = (int) TextAlign.JUSTIFY;
    para.fmt.rule_below = "1;swatch:Black;3";
    st.paras.add (para);
    var p2 = new Paragraph ("Body Text");
    var r1 = new Run ("bold ");
    r1.fmt.bold = 1;
    r1.fmt.size = 13.5;
    p2.runs.add (r1);
    p2.runs.add (new Run.field_run (Fields.merge ("Name")));
    var r2 = new Run (" and «quotes» & ampersands\u2028line");
    r2.cstyle = "Accent";
    r2.fmt.tracking = 25;
    r2.fmt.lang = "it";
    p2.runs.add (r2);
    st.paras.add (p2);
    st.paras.add (new Paragraph.with_text ("", "Body Text"));
    var e = new ShapeItem (ShapeKind.ELLIPSE);
    e.id = p.next_id ();
    e.x = 300;
    e.y = 100;
    e.w = 80;
    e.h = 60;
    e.rotation = 33.5;
    e.flip_h = true;
    e.opacity = 0.75;
    e.wrap = WrapMode.CONTOUR;
    e.wrap_offset = 7;
    e.wrap_side = WrapSide.LARGEST;
    var f = new Fill.linear (ColorRef.swatch ("Cyan"), ColorRef.PAPER, 45);
    f.kind = FillKind.RADIAL;
    f.stops[1].opacity = 0.3;
    e.fill = f;
    e.shadow.enabled = true;
    e.shadow.blur = 9;
    e.layer = l2.id;
    p.pages[0].items.add (e);
    var path = new ShapeItem (ShapeKind.PATH);
    path.id = p.next_id ();
    path.w = 50;
    path.h = 50;
    path.points.add (Point (0, 0));
    path.points.add (Point (1, 0.5));
    path.points.add (Point (0.25, 1));
    path.closed = false;
    path.stroke = new Stroke.with ("#ff0000", 2);
    path.stroke.arrow_end = 1;
    p.pages[0].items.add (path);
    var star = new ShapeItem (ShapeKind.STAR);
    star.id = p.next_id ();
    star.sides = 7;
    star.star_inset = 0.4;
    star.corner = CornerKind.BEVEL;
    star.corner_radius = 5;
    star.locked = true;
    star.hidden = true;
    star.nonprinting = true;
    star.name = "Star";
    var g = new GroupItem ();
    g.id = p.next_id ();
    g.children.add (star);
    var im = new ImageFrame ();
    im.id = p.next_id ();
    uint8[] png = { 0x89, 'P', 'N', 'G', 1, 2, 3 };
    im.media = p.add_media (png, "x.png");
    im.fit = FitMode.MANUAL;
    im.img_x = -12.5;
    im.img_scale = 0.33;
    im.focus_x = 0.2;
    im.merge_field = "Photo";
    im.shape_ellipse = true;
    g.children.add (im);
    g.fit_children ();
    p.pages[2].items.add (g);
    var linked = new ImageFrame ();
    linked.id = p.next_id ();
    linked.link = "/some/where/pic.jpg";
    linked.link_stamp = "123:456";
    p.pages[2].items.add (linked);
    var tb = new TableItem (3, 2);
    tb.id = p.next_id ();
    tb.w = 200;
    tb.h = 60;
    tb.init_cells (p);
    tb.cells[0][0].story.insert_text (TextPos (0, 0), "Head");
    tb.cells[2][1].fill = ColorRef.swatch ("Yellow", 30);
    tb.cells[1][0].valign = 2;
    tb.merge (1, 0, 2, 0);
    tb.header_fill = ColorRef.swatch ("Black", 10);
    p.pages[2].items.add (tb);
    Merge.set_source (p, Csv.parse ("Name,Photo\nAda,/a.png\n\"Line\nbreak\",\n"), "csv", "/data/list.csv");
    p.merge.catalogue = true;
    p.merge.cat_rows = 3;
    return p;
}

void test_xml_lossless () {
    var p = rich ();
    string a = NativeFormat.to_xml (p);
    Publication q;
    try {
        q = NativeFormat.from_xml (a);
    } catch (Error e) {
        assert_not_reached ();
    }
    string b = NativeFormat.to_xml (q);
    if (a != b) {
        var la = a.split (">");
        var lb = b.split (">");
        for (int i = 0; i < int.min (la.length, lb.length); i++) {
            if (la[i] != lb[i]) {
                print ("first difference:\n%s\n%s\n", la[i], lb[i]);
                break;
            }
        }
    }
    assert (a == b);
    assert (q.story (((TextFrame) q.pages[0].items[0]).story).paras[0].text () == "Tab\tseparated  spaces ");
    assert (q.story (((TextFrame) q.pages[0].items[0]).story).paras[1].runs[1].field == "merge:Name");
    assert (q.merge.records[1][0] == "Line\nbreak");
    assert (q.meta.title == "Round Trip & <Test>");
    assert (q.page_label (2) == "B-I");
    assert (q.settings.impose == "nup:2x5:a4");
}

void test_zip_package () {
    var p = rich ();
    uint8[] data;
    try {
        data = NativeFormat.write (p);
    } catch (Error e) {
        assert_not_reached ();
    }
    assert (data[0] == 'P' && data[1] == 'K');
    string head = Bin.head (data, 120);
    assert (head.contains ("mimetype" + NativeFormat.MIME));
    try {
        var zip = new ZipReader (data);
        assert (zip.has ("publication.xml"));
        assert (zip.has ("Thumbnails/thumbnail.png"));
        var th = zip.read ("Thumbnails/thumbnail.png");
        assert (th != null && th[1] == 'P');
        string? html = zip.read_text ("preview.html");
        assert (html != null && html.has_prefix ("<!DOCTYPE html>") && html.contains ("class=\"page\""));
        string? txt = zip.read_text ("content.txt");
        assert (txt != null);
        foreach (var st in p.stories.values) {
            string t = st.plain_text ().strip ();
            if (t != "" && !t.contains ("\xef\xbf\xbc")) assert (txt.contains (t.split ("\n")[0]));
        }
    } catch (Error e) {
        assert_not_reached ();
    }
    assert (FileKind.sniff (data) == FileKind.NATIVE);
    Publication q;
    try {
        q = NativeFormat.read (data);
    } catch (Error e) {
        assert_not_reached ();
    }
    assert (q.media.size == 1);
    foreach (var e in q.media.entries) assert (e.value.get_size () == 7);
    assert (NativeFormat.to_xml (q) == NativeFormat.to_xml (p));
}

void test_document_save_open () {
    string dir = Path.build_filename (Environment.get_tmp_dir (), "publish-native-%lld".printf (get_monotonic_time ()));
    DirUtils.create_with_parents (dir, 0700);
    string path = Path.build_filename (dir, "doc.spub");
    var d = new Document (rich ());
    try {
        d.save_to (path);
    } catch (Error e) {
        assert_not_reached ();
    }
    assert (!d.modified && d.path == path);
    assert (d.pub.meta.created != "");
    Document o;
    try {
        o = Document.open (path);
    } catch (Error e) {
        assert_not_reached ();
    }
    assert (o.kind == FileKind.NATIVE && o.path == path);
    assert (o.pub.base_dir == dir);
    assert (o.pub.pages.size == 3);
    string sla = Path.build_filename (dir, "doc.sla");
    try {
        o.save_to (sla);
        var o2 = Document.open (sla);
        assert (o2.kind == FileKind.SLA);
        assert (o2.pub.pages.size == 3);
    } catch (Error e) {
        assert_not_reached ();
    }
    FileUtils.remove (path);
    FileUtils.remove (sla);
    DirUtils.remove (dir);
}

void test_errors () {
    try {
        NativeFormat.from_xml ("<publication version=\"99\"/>");
        assert_not_reached ();
    } catch (Error e) {
        assert (e is FormatError.UNSUPPORTED);
    }
    try {
        NativeFormat.from_xml ("<other/>");
        assert_not_reached ();
    } catch (Error e) {
        assert (e is FormatError.INVALID);
    }
    try {
        string note;
        Document.load_bytes ("hello".data, "x.txt", out note);
        assert_not_reached ();
    } catch (Error e) {
        assert (e is FormatError.INVALID);
    }
    try {
        var empty = NativeFormat.from_xml ("<publication/>");
        assert (empty.pages.size == 1 && empty.layers.size == 1);
        assert (empty.styles.find_paragraph (StyleSheet.BASIC) != null);
    } catch (Error e) {
        assert_not_reached ();
    }
}

void test_ids_after_load () {
    var p = rich ();
    string x = NativeFormat.to_xml (p).replace ("next-id=\"%d\"".printf (p.id_counter), "next-id=\"1\"");
    Publication q;
    try {
        q = NativeFormat.from_xml (x);
    } catch (Error e) {
        assert_not_reached ();
    }
    int max = 0;
    q.walk ((r) => {
        max = int.max (max, r.item.id);
        return true;
    });
    assert (q.next_id () > max);
}

int main (string[] args) {
    Intl.setlocale (LocaleCategory.ALL, "C.UTF-8");
    Test.init (ref args);
    Test.add_func ("/native/xml-lossless", test_xml_lossless);
    Test.add_func ("/native/zip-package", test_zip_package);
    Test.add_func ("/native/save-open", test_document_save_open);
    Test.add_func ("/native/errors", test_errors);
    Test.add_func ("/native/ids", test_ids_after_load);
    return Test.run ();
}
