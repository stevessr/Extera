from pathlib import Path

settings = Path('lib/pages/settings/settings.dart')
text = settings.read_text()
text = text.replace(
    "import 'package:extera_next/utils/platform_infos.dart';\n",
    "import 'package:extera_next/utils/platform_infos.dart';\n"
    "import 'package:extera_next/utils/profile_field_capabilities.dart';\n",
)
marker = "  void setAboutAction() async {\n"
helper = """  Future<bool> _canModifyProfileField(String field) async {
    final canModify = await Matrix.of(context).client.canModifyOwnProfileField(
      field,
    );
    if (!canModify && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(L10n.of(context).profileFieldManagedByServer)),
      );
    }
    return canModify;
  }

"""
if helper not in text:
    text = text.replace(marker, helper + marker)
text = text.replace(
    "  void setAboutAction() async {\n    final about = await aboutFuture;\n",
    "  void setAboutAction() async {\n"
    "    if (!await _canModifyProfileField(AppConfig.aboutProfileField)) return;\n"
    "    final about = await aboutFuture;\n",
)
text = text.replace(
    "        'xyz.extera.about',\n        {'xyz.extera.about': input},\n",
    "        AppConfig.aboutProfileField,\n"
    "        {AppConfig.aboutProfileField: input},\n",
)
text = text.replace(
    "  void setTimezoneAction() async {\n    final currentTz = await timezoneFuture;\n",
    "  void setTimezoneAction() async {\n"
    "    if (!await _canModifyProfileField('m.tz')) return;\n"
    "    final currentTz = await timezoneFuture;\n",
)
text = text.replace(
    "  void setDisplaynameAction() async {\n    final profile = await profileFuture;\n",
    "  void setDisplaynameAction() async {\n"
    "    if (!await _canModifyProfileField('displayname')) return;\n"
    "    final profile = await profileFuture;\n",
)
text = text.replace(
    "  void setAvatarAction() async {\n    final profile = await profileFuture;\n",
    "  void setAvatarAction() async {\n"
    "    if (!await _canModifyProfileField('avatar_url')) return;\n"
    "    final profile = await profileFuture;\n",
)
text = text.replace(
    "  void setBannerAction() async {\n    final bannerUrl = await bannerFuture;\n",
    "  void setBannerAction() async {\n"
    "    if (!await _canModifyProfileField(AppConfig.bannerProfileField)) return;\n"
    "    final bannerUrl = await bannerFuture;\n",
)
settings.write_text(text)

details = Path('lib/pages/chat_details/chat_details.dart')
text = details.read_text()
text = text.replace(
    "import 'package:extera_next/utils/platform_infos.dart';\n",
    "import 'package:extera_next/utils/platform_infos.dart';\n"
    "import 'package:extera_next/utils/stable_room_topic.dart';\n",
)
text = text.replace(
    "future: () => room.setDescription(input),",
    "future: () => room.setStableDescription(input),",
)
details.write_text(text)

arb = Path('assets/l10n/intl_en.arb')
text = arb.read_text()
if '"profileFieldManagedByServer"' not in text:
    stripped = text.rstrip()
    assert stripped.endswith('}')
    body = stripped[:-1].rstrip()
    if not body.endswith(','):
        body += ','
    arb.write_text(
        body
        + '\n  "profileFieldManagedByServer": "This profile field is managed by your homeserver.",'
        + '\n  "@profileFieldManagedByServer": {}\n}\n'
    )

Path('.github/workflows/apply-stable-msc-wiring.yaml').unlink()
Path('tool/apply_stable_msc_wiring.py').unlink()
