'use strict';
'require view';
'require form';

return view.extend({
	render: function () {
		var m, s, o;

		m = new form.Map('wechatpush', _(''));

		s = m.section(form.NamedSection, 'config', 'wechatpush', _(''));
		s.anonymous = true;
		s.addremove = false;

		o = s.option(form.Value, "font_title", _("Main title color"))
		o.placeholder = '#6A65FF'
		o.description = _('Fill in a #RRGGBB hex color code. Leave empty to use the default #6A65FF. Only takes effect where the push channel supports simple HTML rendering (e.g. WxPusher); other channels ignore the tags.')

		o = s.option(form.Value, "font_success", _("Success message color"))
		o.placeholder = '#92D050'
		o.description = _('Fill in a #RRGGBB hex color code. Leave empty to use the default #92D050.')

		o = s.option(form.Value, "font_fail", _("Failure message color"))
		o.placeholder = '#FF6666'
		o.description = _('Fill in a #RRGGBB hex color code. Leave empty to use the default #FF6666.')

		o = s.option(form.Value, "font_client", _("Client name color"))
		o.placeholder = '#92D050'
		o.description = _('Fill in a #RRGGBB hex color code. Leave empty to use the default #92D050.')

		o = s.option(form.Value, "font_module", _("Module title color"))
		o.placeholder = '#76CCFF'
		o.description = _('Fill in a #RRGGBB hex color code. Leave empty to use the default #76CCFF. Applies to titles like the online-devices list and system status.')

		return m.render();
	}
});
