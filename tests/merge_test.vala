using Singularity.Apps.Publish;

string tmpdir () {
    string d = Path.build_filename (Environment.get_tmp_dir (), "publish-merge-%lld".printf (get_monotonic_time ()));
    DirUtils.create_with_parents (d, 0700);
    return d;
}

void test_csv_basic () {
    var t = Csv.parse ("Name,City,Note\r\nAda,London,\"likes, commas\"\nGrace,\"New\nYork\",\"say \"\"hi\"\"\"\n");
    assert (t.fields.size == 3);
    assert (t.fields[1] == "City");
    assert (t.records.size == 2);
    assert (t.records[0][2] == "likes, commas");
    assert (t.records[1][1] == "New\nYork");
    assert (t.records[1][2] == "say \"hi\"");
}

void test_csv_delimiters () {
    var t = Csv.parse ("\xef\xbb\xbf" + "a;b;c\n1;2;3\n4;5\n");
    assert (t.fields.size == 3 && t.fields[0] == "a");
    assert (t.records.size == 2);
    assert (t.records[1][2] == "");
    var tt = Csv.parse ("x\ty\n1\t2\n");
    assert (tt.fields.size == 2 && tt.records[0][1] == "2");
    var dup = Csv.parse ("Name,Name,\n1,2,3\n");
    assert (dup.fields[1] == "Name 2" && dup.fields[2] == "Field 3");
    var nh = Csv.parse ("1,2\n3,4\n", false);
    assert (nh.fields[0] == "Field 1" && nh.records.size == 2);
    assert (Csv.escape ("a,b") == "\"a,b\"" && Csv.escape ("plain") == "plain");
}

void test_vcard () {
    string vcf = "BEGIN:VCARD\r\nVERSION:3.0\r\nFN:Ada Lovelace\r\nN:Lovelace;Ada;;;\r\nORG:Analytical Engines;R&D\r\nTITLE:Mathematician\r\nEMAIL;TYPE=work:ada@example.org\r\nTEL:+44 20 1234\r\nADR;TYPE=home:;;12 St James\\, Square;London;;SW1Y;United Kingdom\r\nURL:https://example.org\r\nEND:VCARD\r\nBEGIN:VCARD\r\nVERSION:4.0\r\nN:Hopper;Grace;;;\r\nEMAIL:grace@example.org\r\nNOTE:long line fol\r\n ded here\r\nEND:VCARD\r\n";
    var t = VCardReader.parse (vcf);
    assert (t.records.size == 2);
    int fn = t.fields.index_of (_("Full Name"));
    int city = t.fields.index_of (_("City"));
    int street = t.fields.index_of (_("Street"));
    int addr = t.fields.index_of (_("Address"));
    assert (t.records[0][fn] == "Ada Lovelace");
    assert (t.records[0][city] == "London");
    assert (t.records[0][street] == "12 St James, Square");
    assert (t.records[0][addr].contains ("SW1Y London"));
    assert (t.records[0][t.fields.index_of (_("Organization"))] == "Analytical Engines");
    assert (t.records[1][fn] == "Grace Hopper");
}

void test_contacts_dir () {
    string d = tmpdir ();
    string sub = Path.build_filename (d, "account");
    DirUtils.create_with_parents (sub, 0700);
    var pb = new Gdk.Pixbuf (Gdk.Colorspace.RGB, false, 8, 4, 4);
    pb.fill ((uint32) 0xff0000ff);
    uint8[] png;
    try {
        pb.save_to_buffer (out png, "png");
        FileUtils.set_contents (Path.build_filename (d, "a.vcf"), "BEGIN:VCARD\nFN:Zed Last\nEMAIL:z@x.org\nPHOTO;ENCODING=b;TYPE=PNG:" + Base64.encode (png) + "\nEND:VCARD\n");
        FileUtils.set_contents (Path.build_filename (sub, "b.vcf"), "BEGIN:VCARD\nFN:Amy First\nEMAIL:a@x.org\nEND:VCARD\nBEGIN:VCARD\nFN:Zed Last\nEMAIL:z@x.org\nEND:VCARD\n");
    } catch (Error e) {
        assert_not_reached ();
    }
    var dirs = new Gee.ArrayList<string> ();
    dirs.add (d);
    string photos = Path.build_filename (d, "photos");
    var t = VCardReader.load_contacts (dirs, photos);
    assert (t.records.size == 2);
    assert (t.records[0][0] == "Amy First");
    int ph = t.fields.index_of (_("Photo"));
    string photo = t.records[1][ph];
    assert (photo != "" && FileUtils.test (photo, FileTest.IS_REGULAR));
}

Publication letter () {
    var p = Publication.create (null, 1);
    var t = Csv.parse ("Name,City,Photo\nAda,London,\nGrace,Arlington,\nLinus,Helsinki,\n");
    Merge.set_source (p, t, "csv", "/x.csv");
    var f = p.add_text_frame (p.pages[0].items, 40, 40, 300, 60);
    var s = p.story (f.story);
    s.insert_text (TextPos (0, 0), "Dear ");
    s.insert_field (TextPos (0, 5), Fields.merge ("Name"));
    s.insert_text (TextPos (0, 6), " from ");
    s.insert_field (TextPos (0, 12), Fields.merge ("City"));
    var im = new ImageFrame ();
    im.id = p.next_id ();
    im.x = 40;
    im.y = 120;
    im.w = 60;
    im.h = 60;
    im.merge_field = "Photo";
    p.pages[0].items.add (im);
    return p;
}

void test_preview () {
    var p = letter ();
    assert (Merge.used_fields (p).contains ("Name") && Merge.used_fields (p).contains ("Photo"));
    var cache = new LayoutCache (p);
    var f = (TextFrame) p.pages[0].items[0];
    assert (cache.story (f.story).frames[0].lines[0].build.text == "Dear Ada from London");
    p.merge.preview = 2;
    cache.invalidate ();
    assert (cache.story (f.story).frames[0].lines[0].build.text == "Dear Linus from Helsinki");
    p.merge.preview = -1;
    cache.invalidate ();
    assert (cache.story (f.story).frames[0].lines[0].build.text == "Dear «Name» from «City»");
}

void test_expand_letters () {
    var p = letter ();
    var m = Merge.expand (p);
    assert (m.pages.size == 3);
    assert (!m.merge.active ());
    var texts = new Gee.ArrayList<string> ();
    foreach (var pg in m.pages) {
        foreach (var it in pg.items) {
            var t = it as TextFrame;
            if (t != null) texts.add (m.story (t.story).plain_text ());
        }
    }
    assert (texts.size == 3);
    assert (texts[1] == "Dear Grace from Arlington");
    var ids = new Gee.HashSet<int> ();
    m.walk ((r) => {
        assert (!ids.contains (r.item.id));
        ids.add (r.item.id);
        return true;
    });
    var sub = Merge.expand (p, 1, 1);
    assert (sub.pages.size == 1);
    var ex = new Exporter (m);
    string d = tmpdir ();
    string pdf = Path.build_filename (d, "merged.pdf");
    try {
        assert (ex.export_pdf (pdf) == 3);
    } catch (Error e) {
        assert_not_reached ();
    }
    uint8[] data;
    try {
        FileUtils.get_data (pdf, out data);
    } catch (Error e) {
        assert_not_reached ();
    }
    assert (data.length > 1000 && data[0] == '%' && data[1] == 'P');
    FileUtils.remove (pdf);
}

void test_expand_threaded () {
    var p = Publication.create (null, 2);
    Merge.set_source (p, Csv.parse ("Who\nOne\nTwo\n"), "csv", "");
    var f1 = p.add_text_frame (p.pages[0].items, 10, 10, 100, 20);
    var f2 = p.add_text_frame (p.pages[1].items, 10, 10, 400, 600);
    p.link_frames (f1, f2);
    var s = p.story (f1.story);
    s.insert_field (TextPos (0, 0), Fields.merge ("Who"));
    var sb = new StringBuilder ();
    for (int i = 0; i < 30; i++) sb.append (" words to overflow");
    s.insert_text (TextPos (0, 1), sb.str);
    var m = Merge.expand (p);
    assert (m.pages.size == 4);
    var t1 = (TextFrame) m.pages[2].items[0];
    var t2 = (TextFrame) m.pages[3].items[0];
    assert (t1.story == t2.story);
    assert (m.story (t1.story).frames.size == 2);
    assert (m.story (t1.story).plain_text ().has_prefix ("Two words"));
    var cache = new LayoutCache (m);
    assert (!cache.story (t1.story).overset);
}

void test_catalogue () {
    var p = Publication.create (null, 1);
    var names = new StringBuilder ("Product,Price\n");
    for (int i = 0; i < 7; i++) names.append ("Item %d,%d.00\n".printf (i + 1, 10 + i));
    Merge.set_source (p, Csv.parse (names.str), "csv", "");
    var f = p.add_text_frame (p.pages[0].items, 40, 40, 100, 30);
    var s = p.story (f.story);
    s.insert_field (TextPos (0, 0), Fields.merge ("Product"));
    s.insert_text (TextPos (0, 1), " costs ");
    s.insert_field (TextPos (0, 8), Fields.merge ("Price"));
    var box = new ShapeItem (ShapeKind.RECT);
    box.id = p.next_id ();
    box.x = 36;
    box.y = 36;
    box.w = 110;
    box.h = 40;
    p.pages[0].items.insert (0, box);
    var title = p.add_text_frame (p.pages[0].items, 300, 700, 200, 30);
    p.story (title.story).insert_text (TextPos (0, 0), "Catalogue");
    p.merge.catalogue = true;
    p.merge.cat_x = 36;
    p.merge.cat_y = 36;
    p.merge.cat_w = 110;
    p.merge.cat_h = 40;
    p.merge.cat_rows = 2;
    p.merge.cat_cols = 2;
    p.merge.cat_gap_x = 10;
    p.merge.cat_gap_y = 5;
    var m = Merge.expand (p);
    assert (m.pages.size == 2);
    int frames_p1 = 0;
    bool found_item4 = false, found_title = false;
    foreach (var it in m.pages[0].items) {
        var t = it as TextFrame;
        if (t == null) continue;
        frames_p1++;
        string txt = m.story (t.story).plain_text ();
        if (txt == "Item 4 costs 13.00") {
            found_item4 = true;
            assert ((t.x - 160).abs () < 0.01 && (t.y - 85).abs () < 0.01);
        }
        if (txt == "Catalogue") found_title = true;
    }
    assert (frames_p1 == 5 && found_item4 && found_title);
    int frames_p2 = 0;
    foreach (var it in m.pages[1].items) if (it is TextFrame) frames_p2++;
    assert (frames_p2 == 4);
}

void test_image_paths () {
    var p = Publication.create (null, 1);
    p.merge.source_path = "/data/people/list.csv";
    assert (Merge.image_path (p, "photo.jpg") == "/data/people/photo.jpg");
    assert (Merge.image_path (p, "/abs/pic.png") == "/abs/pic.png");
    assert (Merge.image_path (p, "file:///abs/pic.png") == "/abs/pic.png");
    assert (Merge.image_path (p, "") == "");
    p.merge.source_path = "";
    p.base_dir = "/doc";
    assert (Merge.image_path (p, "a.png") == "/doc/a.png");
}

void test_rules_and_images () {
    string d = tmpdir ();
    var sf = new Cairo.ImageSurface (Cairo.Format.RGB24, 8, 8);
    sf.write_to_png (Path.build_filename (d, "ada.png"));
    string csv = Path.build_filename (d, "list.csv");
    var p = Publication.create (null, 1);
    var t = Csv.parse ("Name,Company,Member,@Portrait,Logo\nAda,,yes,ada.png,a.svg\nGrace,Navy,no,missing.png,b.svg\nLinus,,no,,c.jpg\n");
    Merge.set_source (p, t, "csv", csv);
    assert (Merge.image_field (p, "@Portrait") && Merge.image_field (p, "Logo") && !Merge.image_field (p, "Name"));
    assert (Merge.image_fields (p).size == 2);
    var f = p.add_text_frame (p.pages[0].items, 40, 40, 300, 120);
    var s = p.story (f.story);
    s.insert_field (TextPos (0, 0), Fields.merge ("Name"));
    s.split_paragraph (TextPos (0, 1));
    s.insert_field (TextPos (1, 0), Fields.merge ("Company"));
    s.split_paragraph (TextPos (1, 1));
    s.insert_text (TextPos (2, 0), "Rome");
    var im = new ImageFrame ();
    im.id = p.next_id ();
    im.x = 40;
    im.y = 200;
    im.w = 60;
    im.h = 60;
    im.fit = FitMode.FILL;
    im.merge_field = "@Portrait";
    p.pages[0].items.add (im);
    var badge = new ShapeItem (ShapeKind.RECT);
    badge.id = p.next_id ();
    badge.x = 200;
    badge.y = 200;
    badge.w = 40;
    badge.h = 40;
    badge.show_when = new MergeFilter ("Member", FilterOp.EQUALS, "yes");
    p.pages[0].items.add (badge);
    p.merge.image_fit = (int) FitMode.FIT;
    p.merge.hide_missing_images = true;
    var q = NativeFormat.from_xml (NativeFormat.to_xml (p));
    assert (q.merge.image_fit == (int) FitMode.FIT && q.merge.hide_missing_images && q.merge.remove_blank_lines);
    var qb = q.find_item (badge.id).item;
    assert (qb.show_when != null && qb.show_when.field == "Member" && qb.show_when.op == FilterOp.EQUALS && qb.show_when.value == "yes");
    q.base_dir = d;
    var m = Merge.expand (q);
    assert (m.pages.size == 3);
    string[] texts = {};
    int[] images = {}, badges = {};
    foreach (var pg in m.pages) {
        int ni = 0, nb = 0;
        foreach (var it in pg.items) {
            var tf = it as TextFrame;
            if (tf != null) texts += m.story (tf.story).plain_text ();
            var mi = it as ImageFrame;
            if (mi != null) {
                ni++;
                assert (mi.fit == FitMode.FIT && mi.link.has_suffix ("ada.png"));
            }
            if (it is ShapeItem) nb++;
            assert (it.show_when == null);
        }
        images += ni;
        badges += nb;
    }
    assert (texts[0] == "Ada\nRome");
    assert (texts[1] == "Grace\nNavy\nRome");
    assert (images[0] == 1 && images[1] == 0 && images[2] == 0);
    assert (badges[0] == 1 && badges[1] == 0 && badges[2] == 0);
    q.merge.remove_blank_lines = false;
    var keep = Merge.expand (q, 0, 0);
    foreach (var it in keep.pages[0].items) {
        var tf = it as TextFrame;
        if (tf != null) assert (keep.story (tf.story).paras.size == 3);
    }
    q.merge.preview = 1;
    var r = new Renderer (q);
    assert (!r.item_visible (qb));
    q.merge.preview = 0;
    assert (r.item_visible (qb));
}

int main (string[] args) {
    Intl.setlocale (LocaleCategory.ALL, "C.UTF-8");
    Test.init (ref args);
    Test.add_func ("/merge/csv", test_csv_basic);
    Test.add_func ("/merge/csv-delimiters", test_csv_delimiters);
    Test.add_func ("/merge/vcard", test_vcard);
    Test.add_func ("/merge/contacts-dir", test_contacts_dir);
    Test.add_func ("/merge/preview", test_preview);
    Test.add_func ("/merge/expand-letters", test_expand_letters);
    Test.add_func ("/merge/expand-threaded", test_expand_threaded);
    Test.add_func ("/merge/catalogue", test_catalogue);
    Test.add_func ("/merge/image-paths", test_image_paths);
    Test.add_func ("/merge/rules-images", test_rules_and_images);
    return Test.run ();
}
