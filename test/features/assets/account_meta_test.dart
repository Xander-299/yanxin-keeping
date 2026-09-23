/// 账户图标 / 颜色元信息纯函数单测（F7.7 C 批）。
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:yanxin/core/theme/tokens.dart';
import 'package:yanxin/features/assets/application/account_meta.dart';

void main() {
  group('kAccountIcons / kAccountColors 候选集', () {
    test('图标 8 个、key 不重复，颜色 8 个、格式统一', () {
      expect(kAccountIcons.length, 8);
      expect(kAccountIcons.keys.toSet().length, 8);
      expect(kAccountColors.length, 8);
      for (final String hex in kAccountColors) {
        expect(RegExp(r'^#[0-9A-F]{6}$').hasMatch(hex), isTrue,
            reason: '非法颜色候选：$hex');
        expect(parseHexColor(hex), isNotNull, reason: '候选色应可解析：$hex');
      }
    });
  });

  group('accountIcon', () {
    test('null / 空串 / 未知 key → 跟随账户类型图标', () {
      expect(accountIcon(null, 'bank'), accountTypeIcon('bank'));
      expect(accountIcon('', 'cash'), accountTypeIcon('cash'));
      expect(accountIcon('nope', 'wechat'), accountTypeIcon('wechat'));
    });

    test('候选集内的 key → 用自选图标（装饰用，与类型无关）', () {
      expect(accountIcon('piggy', 'bank'), kAccountIcons['piggy']);
      expect(accountIcon('yuan', 'credit'), kAccountIcons['yuan']);
    });
  });

  group('parseHexColor', () {
    test('6 位 hex：带不带 #、大小写均可', () {
      expect(parseHexColor('#FFB627'), const Color(0xFFFFB627));
      expect(parseHexColor('FFB627'), const Color(0xFFFFB627));
      expect(parseHexColor('#ffb627'), const Color(0xFFFFB627));
    });

    test('8 位按 ARGB 解析', () {
      expect(parseHexColor('#80FF6B8A'), const Color(0x80FF6B8A));
    });

    test('非法输入一律 null（不抛异常）', () {
      expect(parseHexColor(null), isNull);
      expect(parseHexColor(''), isNull);
      expect(parseHexColor('#'), isNull);
      expect(parseHexColor('#GGGGGG'), isNull);
      expect(parseHexColor('#FFB62'), isNull); // 5 位
      expect(parseHexColor('#FFB6270'), isNull); // 7 位
      expect(parseHexColor('brandTint'), isNull);
    });
  });

  group('colorToHex', () {
    test('输出大写 #RRGGBB，且与 parseHexColor 互逆', () {
      expect(colorToHex(const Color(0xFFFFB627)), '#FFB627');
      expect(colorToHex(const Color(0xFF5FD068)), '#5FD068');
      // 不透明色之外，alpha 位被剥掉（本批候选色全不透明）
      expect(colorToHex(const Color(0x80FFB627)), '#FFB627');
      for (final String hex in kAccountColors) {
        expect(colorToHex(parseHexColor(hex)!), hex);
      }
    });
  });

  group('accountAvatarColor', () {
    test('null / 空串 / 非法 → 类型默认底色 brandTint（老数据行为不变）', () {
      expect(accountAvatarColor(null), Tok.brandTint);
      expect(accountAvatarColor(''), Tok.brandTint);
      expect(accountAvatarColor('oops'), Tok.brandTint);
    });

    test('合法 hex → 解析后的颜色', () {
      expect(accountAvatarColor('#FF6B8A'), const Color(0xFFFF6B8A));
    });
  });
}
