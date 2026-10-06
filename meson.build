project('singularity-publish', ['vala', 'c'],
  version: '0.1.0',
  meson_version: '>= 0.59.0'
)

i18n = import('i18n')
add_project_arguments('-DGETTEXT_PACKAGE="singularity-publish"', language: 'c')
add_project_arguments('-w', language: 'c')
subdir('po')

cc          = meson.get_compiler('c')
gee_dep     = dependency('gee-0.8')
gio_dep     = dependency('gio-2.0')
xml_dep     = dependency('libxml-2.0')
zlib_dep    = dependency('zlib')
pango_dep   = dependency('pangocairo')
pixbuf_dep  = dependency('gdk-pixbuf-2.0')
math_dep    = cc.find_library('m')
cairo_gobject_dep = dependency('cairo-gobject')
fontconfig_dep = dependency('fontconfig')
pangoft2_dep = dependency('pangoft2')
rsvg_dep    = dependency('librsvg-2.0')
poppler_dep = dependency('poppler-glib')
lcms_dep    = dependency('lcms2', required: false)
sqlite_dep  = dependency('sqlite3', required: false)

core_vala_args = ['--pkg', 'zlib', '--vapidir=' + meson.current_source_dir() / 'vapi']
if lcms_dep.found()
  core_vala_args += ['--pkg', 'lcms2', '-D', 'HAVE_LCMS']
endif
if sqlite_dep.found()
  core_vala_args += ['--pkg', 'sqlite3', '-D', 'HAVE_SQLITE']
endif

core = files(
  'src/color/color_manager.vala',
  'src/model/accessibility.vala',
  'src/model/blocks.vala',
  'src/model/color.vala',
  'src/model/document.vala',
  'src/model/extras.vala',
  'src/model/hyphenator.vala',
  'src/model/items.vala',
  'src/model/macros.vala',
  'src/model/find.vala',
  'src/model/toc.vala',
  'src/model/merge.vala',
  'src/model/preflight.vala',
  'src/model/preflight_profile.vala',
  'src/model/notes.vala',
  'src/model/index_builder.vala',
  'src/model/table_styles.vala',
  'src/model/style_rules.vala',
  'src/model/font_axes.vala',
  'src/model/book.vala',
  'src/model/conditions.vala',
  'src/model/interactive.vala',
  'src/model/linked_tables.vala',
  'src/model/svg_path.vala',
  'src/model/review.vala',
  'src/model/block_pack.vala',
  'src/model/linked_story.vala',
  'src/model/alternate.vala',
  'src/model/publication.vala',
  'src/model/schemes.vala',
  'src/model/story.vala',
  'src/model/styles.vala',
  'src/model/templates.vala',
  'src/model/units.vala',
  'src/io/cfb.vala',
  'src/io/db_reader.vala',
  'src/io/docx_writer.vala',
  'src/io/email_merge.vala',
  'src/io/lettere_mail.vala',
  'src/io/html_export.vala',
  'src/io/idml_reader.vala',
  'src/io/idml_writer.vala',
  'src/io/indd_preview.vala',
  'src/io/epub_export.vala',
  'src/io/web_site.vala',
  'src/io/xml_import.vala',
  'src/io/image_writers.vala',
  'src/io/native.vala',
  'src/io/odg_writer.vala',
  'src/io/pub_reader.vala',
  'src/io/pub_layout.vala',
  'src/io/font_package.vala',
  'src/io/sheet_reader.vala',
  'src/io/sla_reader.vala',
  'src/io/sla_writer.vala',
  'src/io/text_import.vala',
  'src/io/xml.vala',
  'src/io/xps_export.vala',
  'src/io/zip.vala',
  'src/layout/fields.vala',
  'src/layout/para_build.vala',
  'src/layout/composer.vala',
  'src/layout/text_engine.vala',
  'src/render/effects.vala',
  'src/render/exporter.vala',
  'src/render/images.vala',
  'src/render/image_paths.vala',
  'src/render/vector_art.vala',
  'src/render/plates.vala',
  'src/render/separations.vala',
  'src/render/prepress.vala',
  'src/render/renderer.vala',
  'src/render/shapes_lib.vala',
)

pdf_engine_dep = subproject('libsingularity').get_variable('libsingularity_pdf_dep')
core_deps = [rsvg_dep, poppler_dep, pdf_engine_dep, gee_dep, gio_dep, xml_dep, zlib_dep, pango_dep, pixbuf_dep, math_dep, cairo_gobject_dep, fontconfig_dep, pangoft2_dep]
if lcms_dep.found()
  core_deps += [lcms_dep]
endif
if sqlite_dep.found()
  core_deps += [sqlite_dep]
endif

test_env = ['TMPDIR=' + meson.current_build_dir(), 'PUBLISH_FIXTURES=' + meson.current_source_dir() / 'tests' / 'fixtures', 'LC_ALL=C.UTF-8']

model_test = executable('publish-model-test',
  core + files('tests/model_test.vala'),
  dependencies: core_deps,
  vala_args: core_vala_args,
)
test('model', model_test, env: test_env, timeout: 300)

layout_test = executable('publish-layout-test',
  core + files('tests/layout_test.vala'),
  dependencies: core_deps,
  vala_args: core_vala_args,
)
test('layout', layout_test, env: test_env, timeout: 300)

merge_test = executable('publish-merge-test',
  core + files('tests/merge_test.vala'),
  dependencies: core_deps,
  vala_args: core_vala_args,
)
test('merge', merge_test, env: test_env, timeout: 300)

native_test = executable('publish-native-test',
  core + files('tests/native_test.vala'),
  dependencies: core_deps,
  vala_args: core_vala_args,
)
test('native', native_test, env: test_env, timeout: 300)

render_test = executable('publish-render-test',
  core + files('tests/render_test.vala'),
  dependencies: core_deps,
  vala_args: core_vala_args,
)
test('render', render_test, env: test_env, timeout: 300)

sla_test = executable('publish-sla-test',
  core + files('tests/sla_test.vala'),
  dependencies: core_deps,
  vala_args: core_vala_args,
)
test('sla', sla_test, env: test_env, timeout: 300)

idml_test = executable('publish-idml-test',
  core + files('tests/idml_test.vala'),
  dependencies: core_deps,
  vala_args: core_vala_args,
)
test('idml', idml_test, env: test_env, timeout: 300)

pub_test = executable('publish-pub-test',
  core + files('tests/pub_test.vala'),
  dependencies: core_deps,
  vala_args: core_vala_args,
)
test('pub', pub_test, env: test_env, timeout: 300)

foreach t : ['prepress', 'export', 'import', 'features', 'mail', 'indesign']
  test(t, executable('publish-' + t + '-test',
    core + files('tests/' + t + '_test.vala'),
    dependencies: core_deps,
    vala_args: core_vala_args,
  ), env: test_env, timeout: 600)
endforeach

templates_test = executable('publish-templates-test',
  core + files('tests/templates_test.vala'),
  dependencies: core_deps,
  vala_args: core_vala_args,
)
test('templates', templates_test, env: test_env, timeout: 300)

gtk_dep = dependency('gtk4')
libsingularity_dep = dependency('singularity-1.0',
  fallback: ['libsingularity', 'libsingularity_dep']
)

if not meson.is_subproject() and libsingularity_dep.type_name() == 'internal'
  libsingularity_vapi_dir = join_paths(meson.project_build_root(), 'subprojects', 'libsingularity')
  add_project_arguments(['--vapidir=' + libsingularity_vapi_dir], language: 'vala')
endif

gnome = import('gnome')
resources = gnome.compile_resources(
  'singularity-publish-resources',
  'resources/dev.sinty.publish.gresource.xml',
  source_dir: meson.current_source_dir() / 'data' / 'icons',
)

ui = files(
  'src/ui/app.vala',
  'src/ui/canvas.vala',
  'src/ui/canvas_rulers.vala',
  'src/ui/cloud_actions.vala',
  'src/ui/dialogs.vala',
  'src/ui/inspector.vala',
  'src/ui/macros_ui.vala',
  'src/ui/pages_panel.vala',
  'src/ui/panels.vala',
  'src/ui/print_source.vala',
  'src/ui/pro_actions.vala',
  'src/ui/pro_dialogs.vala',
  'src/ui/pro_inspector.vala',
  'src/ui/recipients.vala',
  'src/ui/story_editor.vala',
  'src/ui/symbols.vala',
  'src/ui/typography_dialogs.vala',
  'src/ui/preflight_dialogs.vala',
  'src/ui/book_dialog.vala',
  'src/ui/pathfinder.vala',
  'src/ui/separations_panel.vala',
  'src/ui/review_panel.vala',
  'src/ui/suite_assets.vala',
  'src/ui/library_panel.vala',
  'src/ui/layer_list.vala',
  'src/ui/find_dialog.vala',
  'src/ui/text_edit.vala',
  'src/ui/window.vala',
  'src/io/pdfx_verify.vala',
)

executable('singularity-publish',
  core + ui + files('src/ui/main.vala') + [resources],
  dependencies: core_deps + [gtk_dep, libsingularity_dep, pdf_engine_dep],
  vala_args: core_vala_args,
  install: true
)

ui_test = executable('publish-ui-test',
  core + ui + files('tests/ui_test.vala') + [resources],
  dependencies: core_deps + [gtk_dep, libsingularity_dep, pdf_engine_dep],
  vala_args: core_vala_args,
)
test('ui', ui_test, env: test_env + ['GSETTINGS_BACKEND=memory', 'DISPLAY=', 'WAYLAND_DISPLAY='], timeout: 300)

print_test = executable('publish-print-test',
  core + files('src/ui/print_source.vala', 'tests/print_test.vala'),
  dependencies: core_deps + [gtk_dep, libsingularity_dep],
  vala_args: core_vala_args,
)
test('print', print_test, env: test_env, timeout: 300)

executable('publish-tool',
  core + files('src/cli/automation.vala', 'src/io/pdfx_verify.vala', 'src/cli/main.vala'),
  dependencies: core_deps,
  vala_args: core_vala_args,
  install: true
)

automation_test = executable('publish-automation-test',
  core + files('src/cli/automation.vala', 'src/io/pdfx_verify.vala', 'tests/automation_test.vala'),
  dependencies: core_deps,
  vala_args: core_vala_args,
)
test('automation', automation_test, env: test_env, timeout: 300)

vector_test = executable('publish-vector-test',
  core + files('src/ui/pathfinder.vala', 'src/ui/suite_assets.vala', 'tests/vector_test.vala'),
  dependencies: core_deps + [gtk_dep, libsingularity_dep],
  vala_args: core_vala_args,
)
test('vector', vector_test, env: test_env, timeout: 300)

pdfx_test = executable('publish-pdfx-test',
  core + files('src/io/pdfx_verify.vala', 'tests/pdfx_test.vala'),
  dependencies: core_deps + [pdf_engine_dep],
  vala_args: core_vala_args,
)
test('pdfx', pdfx_test, env: test_env, timeout: 600)

install_data('data/hyphen/hyphen.tex',
  install_dir: get_option('datadir') / 'singularity' / 'hyphen'
)
install_data('data/dev.sinty.publish.desktop',
  install_dir: get_option('datadir') / 'applications'
)
install_data('data/dev.sinty.publish.gschema.xml',
  install_dir: get_option('datadir') / 'glib-2.0' / 'schemas'
)
install_data('data/dev.sinty.publish.json',
  install_dir: get_option('datadir') / 'singularity' / 'app-settings'
)
install_data('data/dev.sinty.publish.open.ini',
  install_dir: get_option('datadir') / 'singularity' / 'files-actions'
)
install_data('data/dev.sinty.publish.xml',
  install_dir: get_option('datadir') / 'mime' / 'packages'
)
install_data('data/icons/dev.sinty.publish.svg',
  install_dir: get_option('datadir') / 'icons' / 'hicolor' / 'scalable' / 'apps'
)
