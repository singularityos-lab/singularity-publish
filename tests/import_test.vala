using Singularity.Apps.Publish;

string outdir () {
    string d = Path.build_filename (Environment.get_tmp_dir (), "publish-import-%lld".printf (get_monotonic_time ()));
    DirUtils.create_with_parents (d, 0700);
    return d;
}

string write_zip (string name, string[,] parts) {
    var z = new ZipWriter ();
    try {
        for (int i = 0; i < parts.length[0]; i++) z.add_text (parts[i, 0], parts[i, 1], i != 0 || parts[i, 0] != "mimetype");
        string p = Path.build_filename (outdir (), name);
        FileUtils.set_data (p, z.finish ());
        return p;
    } catch (Error e) {
        assert_not_reached ();
    }
}

const string W = "xmlns:w=\"http://schemas.openxmlformats.org/wordprocessingml/2006/main\" xmlns:r=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships\"";

void test_docx () {
    string styles = "<?xml version=\"1.0\"?><w:styles " + W + "><w:docDefaults><w:rPrDefault><w:rPr><w:rFonts w:ascii=\"Carlito\"/><w:sz w:val=\"22\"/></w:rPr></w:rPrDefault></w:docDefaults>"
        + "<w:style w:type=\"paragraph\" w:styleId=\"Normal\"><w:name w:val=\"Normal\"/><w:pPr><w:spacing w:after=\"160\"/></w:pPr></w:style>"
        + "<w:style w:type=\"paragraph\" w:styleId=\"Heading1\"><w:name w:val=\"heading 1\"/><w:basedOn w:val=\"Normal\"/><w:next w:val=\"Normal\"/><w:pPr><w:keepNext/><w:jc w:val=\"center\"/></w:pPr><w:rPr><w:b/><w:color w:val=\"2F5496\"/><w:sz w:val=\"32\"/></w:rPr></w:style>"
        + "<w:style w:type=\"character\" w:styleId=\"Strong\"><w:name w:val=\"Strong\"/><w:rPr><w:b/></w:rPr></w:style>"
        + "<w:style w:type=\"paragraph\" w:styleId=\"ListParagraph\"><w:name w:val=\"List Paragraph\"/><w:basedOn w:val=\"Normal\"/><w:pPr><w:ind w:left=\"720\"/></w:pPr></w:style></w:styles>";
    string numbering = "<?xml version=\"1.0\"?><w:numbering " + W + "><w:abstractNum w:abstractNumId=\"0\"><w:lvl w:ilvl=\"0\"><w:numFmt w:val=\"bullet\"/></w:lvl></w:abstractNum><w:abstractNum w:abstractNumId=\"1\"><w:lvl w:ilvl=\"0\"><w:numFmt w:val=\"decimal\"/></w:lvl></w:abstractNum><w:num w:numId=\"1\"><w:abstractNumId w:val=\"0\"/></w:num><w:num w:numId=\"2\"><w:abstractNumId w:val=\"1\"/></w:num></w:numbering>";
    string rels = "<?xml version=\"1.0\"?><Relationships xmlns=\"http://schemas.openxmlformats.org/package/2006/relationships\"><Relationship Id=\"rId9\" Type=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships/hyperlink\" Target=\"https://example.org/\" TargetMode=\"External\"/></Relationships>";
    string doc = "<?xml version=\"1.0\"?><w:document " + W + "><w:body>"
        + "<w:p><w:pPr><w:pStyle w:val=\"Heading1\"/></w:pPr><w:r><w:t>Annual Report</w:t></w:r></w:p>"
        + "<w:p><w:r><w:t xml:space=\"preserve\">Plain </w:t></w:r><w:r><w:rPr><w:i/><w:u w:val=\"single\"/><w:color w:val=\"FF0000\"/><w:sz w:val=\"28\"/></w:rPr><w:t>red italic</w:t></w:r><w:r><w:rPr><w:rStyle w:val=\"Strong\"/></w:rPr><w:t xml:space=\"preserve\"> strong</w:t></w:r><w:r><w:tab/><w:t>tab</w:t><w:br/><w:t>line</w:t></w:r></w:p>"
        + "<w:p><w:hyperlink r:id=\"rId9\"><w:r><w:t>a link</w:t></w:r></w:hyperlink></w:p>"
        + "<w:p><w:pPr><w:pStyle w:val=\"ListParagraph\"/><w:numPr><w:ilvl w:val=\"0\"/><w:numId w:val=\"1\"/></w:numPr></w:pPr><w:r><w:t>bullet one</w:t></w:r></w:p>"
        + "<w:p><w:pPr><w:numPr><w:ilvl w:val=\"1\"/><w:numId w:val=\"2\"/></w:numPr><w:ind w:left=\"1440\" w:hanging=\"360\"/><w:spacing w:before=\"120\" w:line=\"300\" w:lineRule=\"exact\"/></w:pPr><w:r><w:t>number two</w:t></w:r></w:p>"
        + "<w:tbl><w:tr><w:tc><w:p><w:r><w:t>A1</w:t></w:r></w:p></w:tc><w:tc><w:p><w:r><w:t>B1</w:t></w:r></w:p></w:tc></w:tr></w:tbl>"
        + "</w:body></w:document>";
    string[,] parts = { { "[Content_Types].xml", "<Types/>" }, { "word/document.xml", doc }, { "word/styles.xml", styles }, { "word/numbering.xml", numbering }, { "word/_rels/document.xml.rels", rels } };
    string path = write_zip ("t.docx", parts);
    try {
        var t = TextImport.read (path);
        assert (t.format == "docx");
        assert (t.paragraphs.size == 6);
        assert (t.paragraphs[0].style == "Heading 1" && t.paragraphs[0].text () == "Annual Report");
        var h1 = t.styles.find_paragraph ("Heading 1");
        assert (h1 != null && h1.based_on == "Normal" && h1.next == "Normal" && h1.chars.bold == 1 && h1.chars.size == 16 && h1.chars.color == "#2f5496" && h1.para.align == 1 && h1.para.keep_next == 1);
        assert (t.styles.find_paragraph ("Normal").chars.font == "Carlito");
        assert (t.styles.find_character ("Strong") != null);
        var p1 = t.paragraphs[1];
        assert (p1.text () == "Plain red italic strong\ttab line");
        Run? red = null, strong = null;
        foreach (var r in p1.runs) {
            if (r.text == "red italic") red = r;
            if (r.cstyle == "Strong") strong = r;
        }
        assert (red != null && red.fmt.italic == 1 && red.fmt.underline == 1 && red.fmt.color == "#ff0000" && red.fmt.size == 14);
        assert (strong != null);
        assert (t.paragraphs[2].runs[0].fmt.link == "https://example.org/");
        assert (t.paragraphs[3].fmt.list_type == 1 && t.paragraphs[3].style == "List Paragraph");
        assert (t.paragraphs[4].fmt.list_type == 2 && t.paragraphs[4].fmt.list_level == 1);
        assert (t.paragraphs[4].fmt.left_indent == 72 && t.paragraphs[4].fmt.first_indent == -18 && t.paragraphs[4].fmt.space_before == 6 && t.paragraphs[4].fmt.leading == 15);
        assert (t.paragraphs[5].text () == "A1\tB1");
        var pub = Publication.create (null, 1);
        int n = TextImport.merge_styles (pub, t.styles, false);
        assert (n == 2);
        assert (pub.styles.find_paragraph ("Heading 1").chars.size == 26);
        TextImport.merge_styles (pub, t.styles, true);
        assert (pub.styles.find_paragraph ("Heading 1").chars.size == 16);
        var st = new Story (1);
        var end = TextImport.insert_into_story (pub, st, TextPos (0, 0), t, true);
        assert (st.paras.size == 6 && end.para == 5);
        assert (st.paras[0].style == "Heading 1");
        var st2 = new Story (2);
        st2.paras[0].style = "Body Text";
        TextImport.insert_into_story (pub, st2, TextPos (0, 0), t, false);
        foreach (var p in st2.paras) assert (p.style == "Body Text");
        assert (st2.paras[2].runs[0].fmt.link == "https://example.org/");
    } catch (Error e) {
        warning ("%s", e.message);
        assert_not_reached ();
    }
}

void test_odt () {
    string ns = "xmlns:office=\"urn:oasis:names:tc:opendocument:xmlns:office:1.0\" xmlns:style=\"urn:oasis:names:tc:opendocument:xmlns:style:1.0\" xmlns:text=\"urn:oasis:names:tc:opendocument:xmlns:text:1.0\" xmlns:fo=\"urn:oasis:names:tc:opendocument:xmlns:xsl-fo-compatible:1.0\" xmlns:xlink=\"http://www.w3.org/1999/xlink\" xmlns:table=\"urn:oasis:names:tc:opendocument:xmlns:table:1.0\"";
    string styles = "<?xml version=\"1.0\"?><office:document-styles " + ns + "><office:font-face-decls><style:font-face style:name=\"Liberation Serif\" svg:font-family=\"'Liberation Serif'\" xmlns:svg=\"urn:oasis:names:tc:opendocument:xmlns:svg-compatible:1.0\"/></office:font-face-decls><office:styles>"
        + "<style:style style:name=\"Standard\" style:family=\"paragraph\"><style:text-properties style:font-name=\"Liberation Serif\" fo:font-size=\"12pt\"/></style:style>"
        + "<style:style style:name=\"Heading_20_1\" style:display-name=\"Heading 1\" style:family=\"paragraph\" style:parent-style-name=\"Standard\"><style:paragraph-properties fo:text-align=\"center\" fo:margin-top=\"0.5cm\"/><style:text-properties fo:font-size=\"20pt\" fo:font-weight=\"bold\" fo:color=\"#003366\"/></style:style>"
        + "<style:style style:name=\"Emphasis\" style:family=\"text\"><style:text-properties fo:font-style=\"italic\"/></style:style>"
        + "</office:styles></office:document-styles>";
    string content = "<?xml version=\"1.0\"?><office:document-content " + ns + "><office:automatic-styles>"
        + "<style:style style:name=\"P1\" style:family=\"paragraph\" style:parent-style-name=\"Standard\"><style:paragraph-properties fo:margin-left=\"1in\" fo:text-indent=\"-0.25in\"/></style:style>"
        + "<style:style style:name=\"T1\" style:family=\"text\"><style:text-properties fo:font-weight=\"bold\" style:text-underline-style=\"solid\"/></style:style>"
        + "</office:automatic-styles><office:body><office:text>"
        + "<text:h text:style-name=\"Heading_20_1\" text:outline-level=\"1\">Title Here</text:h>"
        + "<text:p text:style-name=\"P1\">Hello<text:s text:c=\"3\"/>world <text:span text:style-name=\"T1\">bold</text:span> and <text:span text:style-name=\"Emphasis\">em</text:span><text:tab/>x<text:line-break/>y <text:a xlink:href=\"https://odf.example/\">site</text:a></text:p>"
        + "<text:list><text:list-item><text:p>item one</text:p></text:list-item><text:list-item><text:p>item two</text:p></text:list-item></text:list>"
        + "</office:text></office:body></office:document-content>";
    string[,] parts = { { "mimetype", "application/vnd.oasis.opendocument.text" }, { "content.xml", content }, { "styles.xml", styles } };
    string path = write_zip ("t.odt", parts);
    try {
        var t = TextImport.read (path);
        assert (t.format == "odt");
        assert (t.paragraphs.size == 4);
        assert (t.paragraphs[0].style == "Heading 1" && t.paragraphs[0].text () == "Title Here");
        var h = t.styles.find_paragraph ("Heading 1");
        assert (h != null && h.based_on == "Standard" && h.chars.size == 20 && h.chars.bold == 1 && h.para.align == 1);
        assert (Math.fabs (h.para.space_before - 14.17) < 0.1);
        assert (t.styles.find_paragraph ("Standard").chars.font == "Liberation Serif");
        var p = t.paragraphs[1];
        assert (p.style == "Standard");
        assert (p.fmt.left_indent == 72 && p.fmt.first_indent == -18);
        assert (p.text () == "Hello   world bold and em\tx\u2028y site");
        Run? bold = null, em = null, link = null;
        foreach (var r in p.runs) {
            if (r.text == "bold") bold = r;
            if (r.text == "em") em = r;
            if (r.text == "site") link = r;
        }
        assert (bold != null && bold.fmt.bold == 1 && bold.fmt.underline == 1);
        assert (em != null && em.cstyle == "Emphasis");
        assert (link != null && link.fmt.link == "https://odf.example/");
        assert (t.paragraphs[2].fmt.list_type == 1 && t.paragraphs[3].text () == "item two");
    } catch (Error e) {
        warning ("%s", e.message);
        assert_not_reached ();
    }
}

void test_rtf_txt () {
    string rtf = "{\\rtf1\\ansi\\deff0{\\fonttbl{\\f0 Times New Roman;}{\\f1 Arial;}}{\\colortbl;\\red255\\green0\\blue0;}\n\\pard\\qc\\f1\\fs32\\b Title\\b0\\par\n\\pard\\li720\\fi-360\\sa120 Normal \\i italic\\i0  \\cf1 red\\cf0  caf\\'e9 \\u8364? end\\line next\\par}";
    var t = TextImport.read_rtf (rtf);
    assert (t.paragraphs.size == 2);
    assert (t.paragraphs[0].text () == "Title");
    assert (t.paragraphs[0].fmt.align == 1);
    assert (t.paragraphs[0].runs[0].fmt.bold == 1 && t.paragraphs[0].runs[0].fmt.size == 16 && t.paragraphs[0].runs[0].fmt.font == "Arial");
    var p = t.paragraphs[1];
    assert (p.text () == "Normal italic red café € end next");
    assert (p.fmt.left_indent == 36 && p.fmt.first_indent == -18 && p.fmt.space_after == 6);
    bool italic = false, red = false;
    foreach (var r in p.runs) {
        if (r.text == "italic" && r.fmt.italic == 1) italic = true;
        if (r.text == "red" && r.fmt.color == "#ff0000") red = true;
    }
    assert (italic && red);
    uint8[] utf16 = { 0xFF, 0xFE, 'H', 0, 'i', 0, 0x0A, 0, 0xE9, 0, 0x3D, 0xD8, 0x00, 0xDE };
    try {
        var tt = TextImport.read_data (utf16, "note.txt");
        assert (tt.paragraphs.size == 2 && tt.paragraphs[0].text () == "Hi" && tt.paragraphs[1].text () == "é😀");
        uint8[] latin = { 'c', 'a', 'f', 0xE9, 0x80 };
        assert (TextImport.read_data (latin, "x.txt").paragraphs[0].text () == "café€");
        uint8[] doc = { 0xD0, 0xCF, 0x11, 0xE0, 0xA1, 0xB1, 0x1A, 0xE1 };
        bool failed = false;
        try {
            TextImport.read_data (doc, "old.doc");
        } catch (Error e) {
            failed = e.message.contains (".docx");
        }
        assert (failed);
    } catch (Error e) {
        warning ("%s", e.message);
        assert_not_reached ();
    }
}

void test_xlsx () {
    string wb = "<?xml version=\"1.0\"?><workbook xmlns=\"http://schemas.openxmlformats.org/spreadsheetml/2006/main\" xmlns:r=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships\"><sheets><sheet name=\"People\" sheetId=\"1\" r:id=\"rId1\"/><sheet name=\"Other\" sheetId=\"2\" r:id=\"rId2\"/></sheets></workbook>";
    string rels = "<?xml version=\"1.0\"?><Relationships xmlns=\"http://schemas.openxmlformats.org/package/2006/relationships\"><Relationship Id=\"rId1\" Target=\"worksheets/sheet1.xml\" Type=\"x\"/><Relationship Id=\"rId2\" Target=\"worksheets/sheet2.xml\" Type=\"x\"/></Relationships>";
    string ss = "<?xml version=\"1.0\"?><sst xmlns=\"http://schemas.openxmlformats.org/spreadsheetml/2006/main\"><si><t>Name</t></si><si><t>Joined</t></si><si><t>City</t></si><si><r><t>Ann</t></r><r><t xml:space=\"preserve\"> Lee</t></r></si><si><t>Rome</t></si></sst>";
    string styles = "<?xml version=\"1.0\"?><styleSheet xmlns=\"http://schemas.openxmlformats.org/spreadsheetml/2006/main\"><numFmts><numFmt numFmtId=\"164\" formatCode=\"dd/mm/yyyy\"/></numFmts><cellXfs><xf numFmtId=\"0\"/><xf numFmtId=\"164\"/><xf numFmtId=\"2\"/></cellXfs></styleSheet>";
    string sheet1 = "<?xml version=\"1.0\"?><worksheet xmlns=\"http://schemas.openxmlformats.org/spreadsheetml/2006/main\"><sheetData>"
        + "<row r=\"1\"><c r=\"A1\" t=\"s\"><v>0</v></c><c r=\"B1\" t=\"s\"><v>1</v></c><c r=\"C1\" t=\"s\"><v>2</v></c><c r=\"D1\" t=\"inlineStr\"><is><t>Score</t></is></c></row>"
        + "<row r=\"2\"><c r=\"A2\" t=\"s\"><v>3</v></c><c r=\"B2\" s=\"1\"><v>45658</v></c><c r=\"C2\" t=\"s\"><v>4</v></c><c r=\"D2\" s=\"2\"><v>12.5</v></c></row>"
        + "<row r=\"4\"><c r=\"A4\" t=\"inlineStr\"><is><t>Bo</t></is></c><c r=\"D4\"><v>7</v></c><c r=\"E4\" t=\"b\"><v>1</v></c></row>"
        + "</sheetData></worksheet>";
    string sheet2 = "<?xml version=\"1.0\"?><worksheet xmlns=\"http://schemas.openxmlformats.org/spreadsheetml/2006/main\"><sheetData><row r=\"1\"><c r=\"B1\" t=\"inlineStr\"><is><t>Only</t></is></c></row></sheetData></worksheet>";
    string[,] parts = { { "[Content_Types].xml", "<Types/>" }, { "xl/workbook.xml", wb }, { "xl/_rels/workbook.xml.rels", rels }, { "xl/sharedStrings.xml", ss }, { "xl/styles.xml", styles }, { "xl/worksheets/sheet1.xml", sheet1 }, { "xl/worksheets/sheet2.xml", sheet2 } };
    string path = write_zip ("people.xlsx", parts);
    try {
        var names = SheetReader.sheet_names (path);
        assert (names.size == 2 && names[0] == "People" && names[1] == "Other");
        var t = SheetReader.read (path, 0, true);
        assert (t.fields.size == 5);
        assert (t.fields[0] == "Name" && t.fields[1] == "Joined" && t.fields[3] == "Score");
        assert (t.records.size == 2);
        assert (t.records[0][0] == "Ann Lee" && t.records[0][1] == "2025-01-01" && t.records[0][2] == "Rome" && t.records[0][3] == "12.5");
        assert (t.records[1][0] == "Bo" && t.records[1][3] == "7" && t.records[1][4] == "TRUE");
        var t2 = SheetReader.read (path, 1, false);
        assert (t2.records.size == 1 && t2.records[0][1] == "Only");
        assert (SheetReader.column_index ("AB12") == 27);
    } catch (Error e) {
        warning ("%s", e.message);
        assert_not_reached ();
    }
}

void test_ods () {
    string ns = "xmlns:office=\"urn:oasis:names:tc:opendocument:xmlns:office:1.0\" xmlns:table=\"urn:oasis:names:tc:opendocument:xmlns:table:1.0\" xmlns:text=\"urn:oasis:names:tc:opendocument:xmlns:text:1.0\"";
    string content = "<?xml version=\"1.0\"?><office:document-content " + ns + "><office:body><office:spreadsheet><table:table table:name=\"List\">"
        + "<table:table-row><table:table-cell office:value-type=\"string\"><text:p>Name</text:p></table:table-cell><table:table-cell table:number-columns-repeated=\"2\" office:value-type=\"string\"><text:p>Dup</text:p></table:table-cell><table:table-cell office:value-type=\"string\"><text:p>When</text:p></table:table-cell></table:table-row>"
        + "<table:table-row><table:table-cell office:value-type=\"string\"><text:p>Eve</text:p></table:table-cell><table:table-cell office:value-type=\"float\" office:value=\"3\"><text:p>3</text:p></table:table-cell><table:covered-table-cell/><table:table-cell office:value-type=\"date\" office:date-value=\"2024-05-06\"><text:p>06/05/24</text:p></table:table-cell></table:table-row>"
        + "<table:table-row table:number-rows-repeated=\"1000\"><table:table-cell table:number-columns-repeated=\"1024\"/></table:table-row>"
        + "</table:table></office:spreadsheet></office:body></office:document-content>";
    string[,] parts = { { "mimetype", "application/vnd.oasis.opendocument.spreadsheet" }, { "content.xml", content } };
    string path = write_zip ("list.ods", parts);
    try {
        assert (SheetReader.sheet_names (path)[0] == "List");
        var t = SheetReader.read (path, 0, true);
        assert (t.fields.size == 4 && t.fields[1] == "Dup" && t.fields[2] == "Dup 2");
        assert (t.records.size == 1);
        assert (t.records[0][0] == "Eve" && t.records[0][1] == "3" && t.records[0][2] == "" && t.records[0][3] == "2024-05-06");
    } catch (Error e) {
        warning ("%s", e.message);
        assert_not_reached ();
    }
}

void test_sqlite () {
    if (!DbReader.available ()) {
        print ("SQLite support not built, database test skipped\n");
        return;
    }
    string path = Path.build_filename (outdir (), "people.sdb");
#if HAVE_SQLITE
    Sqlite.Database db;
    assert (Sqlite.Database.open (path, out db) == Sqlite.OK);
    assert (db.exec ("CREATE TABLE people (name TEXT, age INTEGER, score REAL, photo BLOB); INSERT INTO people VALUES ('Ann', 31, 4.5, NULL), ('Bob', 9, 7.0, x'00ff'); CREATE VIEW adults AS SELECT name FROM people WHERE age >= 18;") == Sqlite.OK);
    db = null;
#endif
    try {
        var tables = DbReader.tables (path);
        assert (tables.contains ("people") && tables.contains ("adults"));
        var t = DbReader.read_table (path, "people");
        assert (t.fields.size == 4 && t.fields[1] == "age");
        assert (t.records.size == 2 && t.records[0][0] == "Ann" && t.records[0][1] == "31" && t.records[0][2] == "4.5" && t.records[1][2] == "7" && t.records[0][3] == "");
        var v = DbReader.read_table (path, "adults");
        assert (v.records.size == 1 && v.records[0][0] == "Ann");
        var q = DbReader.query (path, "SELECT name, age * 2 AS twice FROM people ORDER BY age");
        assert (q.fields[1] == "twice" && q.records[0][0] == "Bob" && q.records[0][1] == "18");
        bool refused = false;
        try {
            DbReader.query (path, "DELETE FROM people");
        } catch (Error e) {
            refused = true;
        }
        assert (refused);
        refused = false;
        try {
            DbReader.query (path, "SELECT 1; DROP TABLE people");
        } catch (Error e) {
            refused = true;
        }
        assert (refused);
        assert (DbReader.read_table (path, "people").records.size == 2);
        refused = false;
        try {
            DbReader.read_table (path, "nope\"; DROP TABLE people; --");
        } catch (Error e) {
            refused = true;
        }
        assert (refused);
    } catch (Error e) {
        warning ("%s", e.message);
        assert_not_reached ();
    }
}

void main (string[] args) {
    Test.init (ref args);
    Test.add_func ("/import/docx", test_docx);
    Test.add_func ("/import/odt", test_odt);
    Test.add_func ("/import/rtf-txt", test_rtf_txt);
    Test.add_func ("/import/xlsx", test_xlsx);
    Test.add_func ("/import/ods", test_ods);
    Test.add_func ("/import/sqlite", test_sqlite);
    Test.run ();
}
