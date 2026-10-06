namespace Singularity.Apps.Publish {

    public class PdfxReport {
        public bool passed = false;
        public string version = "";
        public Gee.ArrayList<string> problems = new Gee.ArrayList<string> ();

        public static string version_of (ColorMode mode) {
            switch (mode) {
                case ColorMode.PDFX1A: return "PDF/X-1a";
                case ColorMode.PDFX3: return "PDF/X-3";
                case ColorMode.PDFX4: return "PDF/X-4";
                default: return "";
            }
        }

        public static PdfxReport verify (string path, ColorMode mode) {
            var r = new PdfxReport ();
            r.version = version_of (mode);
            if (r.version == "") return r;
            try {
                var doc = Singularity.Pdf.Document.open_file (path);
                foreach (var i in Singularity.Pdf.Standards.check_pdfx (doc, r.version)) {
                    r.problems.add (i.page >= 0 ? _("Page %d: %s").printf (i.page + 1, i.message) : i.message);
                }
            } catch (Error e) {
                r.problems.add (e.message);
            }
            r.passed = r.problems.size == 0;
            return r;
        }
    }
}
