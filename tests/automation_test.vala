using Singularity.Apps.Publish;

void test_automation () {
    string dir = Path.build_filename (Environment.get_tmp_dir (), "publish-tool-%lld".printf (get_monotonic_time ()));
    DirUtils.create_with_parents (dir, 0700);
    var p = Publication.create (null, 1);
    p.styles.find_paragraph (StyleSheet.BASIC).chars.font = "DejaVu Sans";
    var t = p.add_text_frame (p.pages[0].items, 40, 40, 300, 100);
    t.name = "headline";
    p.story (t.story).paras[0].runs[0].text = "Old title";
    string doc = Path.build_filename (dir, "flyer.spub");
    string script = Path.build_filename (dir, "job.macro");
    try {
        FileUtils.set_data (doc, NativeFormat.write (p));
        FileUtils.set_contents (script, "new-page\nmessage pages: {pages.count}\n");
    } catch (Error e) {
        error (e.message);
    }
    string out_s;
    string pdf = Path.build_filename (dir, "flyer.pdf");
    string epub = Path.build_filename (dir, "flyer.epub");
    int st = Automation.run ({ "publish-tool", doc, "--set-text", "headline=New title", "--run", script, "--update", "--export", pdf, "--export", epub, "--save" }, out out_s);
    if (st != 0) error ("status %d: %s", st, out_s);
    assert (out_s.contains ("pages: 2"));
    assert (FileUtils.test (pdf, FileTest.EXISTS) && FileUtils.test (epub, FileTest.EXISTS));
    Publication q;
    try {
        q = Automation.open (doc);
    } catch (Error e) {
        error (e.message);
    }
    assert (q.pages.size == 2);
    bool found = false;
    foreach (var s in q.stories.values) if (s.plain_text () == "New title") found = true;
    assert (found);
    st = Automation.run ({ "publish-tool", doc, "--preflight", "Basic" }, out out_s);
    assert (st == 0 || st == 3);
    st = Automation.run ({ "publish-tool", doc, "--bogus" }, out out_s);
    assert (st == 2 && out_s.contains ("Unknown option"));
    st = Automation.run ({ "publish-tool" }, out out_s);
    assert (st == 1 && out_s.contains ("Usage"));
}

int main (string[] args) {
    Intl.setlocale (LocaleCategory.ALL, "C.UTF-8");
    Test.init (ref args);
    Test.add_func ("/automation/tool", test_automation);
    return Test.run ();
}
