// ignore: avoid_web_libraries_in_flutter, deprecated_member_use
import 'dart:html' as html;
import 'dart:ui_web' as ui_web;
import 'package:flutter/material.dart';

bool _gformFactoryRegistered = false;
const String _gformViewType = 'gform-iframe-view';

Widget buildGFormIframe(String url) {
  if (!_gformFactoryRegistered) {
    ui_web.platformViewRegistry.registerViewFactory(
      _gformViewType,
      (int viewId) {
        final iframe = html.IFrameElement()
          ..src = url
          ..style.border = 'none'
          ..style.width = '100%'
          ..style.height = '100%'
          ..setAttribute('frameborder', '0')
          ..setAttribute('marginheight', '0')
          ..setAttribute('marginwidth', '0');
        return iframe;
      },
    );
    _gformFactoryRegistered = true;
  }
  return const HtmlElementView(viewType: _gformViewType);
}
