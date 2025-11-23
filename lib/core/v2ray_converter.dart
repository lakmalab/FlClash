import 'dart:convert';
import 'dart:typed_data';

class V2RayConverter {
  // Main conversion method with comprehensive error handling
  static List<Map<String, dynamic>> convertV2RayConfig(String configData) {
    final proxies = <Map<String, dynamic>>[];
    final names = <String, int>{};

    try {
      final data = _safeDecodeBase64(configData);
      final lines = data.split('\n');

      for (final line in lines) {
        final trimmedLine = line.trim();
        if (trimmedLine.isEmpty) continue;

        try {
          final parsedProxy = _parseProxyLine(trimmedLine, names);
          if (parsedProxy != null && _validateProxy(parsedProxy)) {
            proxies.add(parsedProxy);
          }
        } catch (e) {

          continue;
        }
      }

      if (proxies.isEmpty) {
        throw Exception('No valid proxies found in configuration');
      }

      return proxies;
    } catch (e) {
      throw Exception('Failed to parse V2Ray config: $e');
    }
  }

  // Safe base64 decoder
  static String _safeDecodeBase64(String data) {
    try {
      final bytes = base64.decode(data);
      return utf8.decode(bytes);
    } catch (e) {
      // If not base64, return as-is
      return data;
    }
  }

  // Main proxy line parser with error handling
  static Map<String, dynamic>? _parseProxyLine(String line, Map<String, int> names) {
    try {
      if (!line.contains('://')) return null;

      final parts = line.split('://');
      if (parts.length < 2) return null;

      final scheme = parts[0].toLowerCase().trim();

      switch (scheme) {
        case 'hysteria':
          return _parseHysteria(line, names);
        case 'hysteria2':
        case 'hy2':
          return _parseHysteria2(line, names);
        case 'tuic':
          return _parseTuic(line, names);
        case 'trojan':
          return _parseTrojan(line, names);
        case 'vless':
          return _parseVLess(line, names);
        case 'vmess':
          return _parseVMess(line, names);
        case 'ss':
          return _parseSS(line, names);
        case 'ssr':
          return _parseSSR(line, names);
        case 'socks':
        case 'socks5':
        case 'socks5h':
        case 'http':
        case 'https':
          return _parseSocksHttp(line, names);
        default:
          return null;
      }
    } catch (e) {
      return null;
    }
  }

  // Validate proxy structure - CRITICAL FIX FOR HEADERS
  static bool _validateProxy(Map<String, dynamic> proxy) {
    try {
      // Basic required fields
      if (!proxy.containsKey('name') || proxy['name'].toString().isEmpty) return false;
      if (!proxy.containsKey('type') || proxy['type'].toString().isEmpty) return false;
      if (!proxy.containsKey('server') || proxy['server'].toString().isEmpty) return false;
      if (!proxy.containsKey('port')) return false;

      // Validate port
      final port = proxy['port'];
      if (port is String) {
        final portNum = int.tryParse(port);
        if (portNum == null || portNum <= 0 || portNum > 65535) return false;
      } else if (port is int) {
        if (port <= 0 || port > 65535) return false;
      } else {
        return false;
      }

      // FIX: Validate and fix nested structures
      if (proxy.containsKey('ws-opts')) {
        if (proxy['ws-opts'] is! Map) return false;
        final wsOpts = proxy['ws-opts'] as Map<String, dynamic>;

        // CRITICAL: Ensure headers is a proper Map, not a string
        if (wsOpts.containsKey('headers')) {
          if (wsOpts['headers'] is String) {
            // Try to parse string as map or replace with empty map
            wsOpts['headers'] = <String, dynamic>{};
          } else if (wsOpts['headers'] is! Map) {
            return false;
          }
        } else {
          wsOpts['headers'] = <String, dynamic>{};
        }
      }

      if (proxy.containsKey('http-opts')) {
        if (proxy['http-opts'] is! Map) return false;
        final httpOpts = proxy['http-opts'] as Map<String, dynamic>;

        // Ensure headers is a map
        if (httpOpts.containsKey('headers')) {
          if (httpOpts['headers'] is String) {
            httpOpts['headers'] = <String, dynamic>{};
          } else if (httpOpts['headers'] is! Map) {
            return false;
          }
        }
      }

      if (proxy.containsKey('h2-opts')) {
        if (proxy['h2-opts'] is! Map) return false;
        final h2Opts = proxy['h2-opts'] as Map<String, dynamic>;

        if (h2Opts.containsKey('headers')) {
          if (h2Opts['headers'] is String) {
            h2Opts['headers'] = <String, dynamic>{};
          } else if (h2Opts['headers'] is! Map) {
            return false;
          }
        }
      }

      if (proxy.containsKey('grpc-opts') && proxy['grpc-opts'] is! Map) return false;

      return true;
    } catch (e) {
      return false;
    }
  }

  // Generate unique name
  static String _uniqueName(Map<String, int> names, String name) {
    final cleanName = name.isEmpty ? 'proxy' : name;

    if (names.containsKey(cleanName)) {
      final index = names[cleanName]! + 1;
      names[cleanName] = index;
      return '$cleanName-${index.toString().padLeft(2, '0')}';
    } else {
      names[cleanName] = 0;
      return cleanName;
    }
  }

  // Safe URI parser
  static Uri? _safeParseUri(String line) {
    try {
      return Uri.parse(line);
    } catch (e) {
      return null;
    }
  }

  // Hysteria parser
  static Map<String, dynamic>? _parseHysteria(String line, Map<String, int> names) {
    try {
      final uri = _safeParseUri(line);
      if (uri == null) return null;

      final query = uri.queryParameters;
      final name = _uniqueName(names, uri.fragment);

      final hysteria = <String, dynamic>{
        'name': name,
        'type': 'hysteria',
        'server': uri.host,
        'port': uri.hasPort ? uri.port : 443,
        'udp': true,
      };

      if (query.containsKey('peer') && query['peer']!.isNotEmpty) {
        hysteria['sni'] = query['peer'];
      }
      if (query.containsKey('obfs') && query['obfs']!.isNotEmpty) {
        hysteria['obfs'] = query['obfs'];
      }
      if (query.containsKey('alpn') && query['alpn']!.isNotEmpty) {
        hysteria['alpn'] = query['alpn']!.split(',');
      }
      if (query.containsKey('auth') && query['auth']!.isNotEmpty) {
        hysteria['auth_str'] = query['auth'];
      }
      if (query.containsKey('protocol')) {
        hysteria['protocol'] = query['protocol'];
      }

      var up = query['up'] ?? query['upmbps'];
      var down = query['down'] ?? query['downmbps'];
      if (up != null) hysteria['up'] = up;
      if (down != null) hysteria['down'] = down;

      hysteria['skip-cert-verify'] = query['insecure'] == '1';

      return hysteria;
    } catch (e) {
      return null;
    }
  }

  // Hysteria2 parser
  static Map<String, dynamic>? _parseHysteria2(String line, Map<String, int> names) {
    try {
      final uri = _safeParseUri(line);
      if (uri == null) return null;

      final query = uri.queryParameters;
      final name = _uniqueName(names, uri.fragment);

      final hysteria2 = <String, dynamic>{
        'name': name,
        'type': 'hysteria2',
        'server': uri.host,
        'port': uri.hasPort ? uri.port : 443,
        'udp': true,
      };

      if (query.containsKey('obfs')) hysteria2['obfs'] = query['obfs'];
      if (query.containsKey('obfs-password')) hysteria2['obfs-password'] = query['obfs-password'];
      if (query.containsKey('sni')) hysteria2['sni'] = query['sni'];
      if (query.containsKey('alpn') && query['alpn']!.isNotEmpty) {
        hysteria2['alpn'] = query['alpn']!.split(',');
      }
      if (uri.userInfo.isNotEmpty) {
        hysteria2['password'] = uri.userInfo;
      }
      if (query.containsKey('pinSHA256')) hysteria2['fingerprint'] = query['pinSHA256'];
      if (query.containsKey('down')) hysteria2['down'] = query['down'];
      if (query.containsKey('up')) hysteria2['up'] = query['up'];

      hysteria2['skip-cert-verify'] = query['insecure'] == '1';

      return hysteria2;
    } catch (e) {
      return null;
    }
  }

  // TUIC parser
  static Map<String, dynamic>? _parseTuic(String line, Map<String, int> names) {
    try {
      final uri = _safeParseUri(line);
      if (uri == null) return null;

      final query = uri.queryParameters;
      final name = _uniqueName(names, uri.fragment);

      final tuic = <String, dynamic>{
        'name': name,
        'type': 'tuic',
        'server': uri.host,
        'port': uri.hasPort ? uri.port : 443,
        'udp': true,
      };

      if (uri.userInfo.contains(':')) {
        final parts = uri.userInfo.split(':');
        tuic['uuid'] = parts[0];
        tuic['password'] = parts[1];
      } else {
        tuic['token'] = uri.userInfo;
      }

      if (query.containsKey('congestion_control')) {
        tuic['congestion-controller'] = query['congestion_control'];
      }
      if (query.containsKey('alpn') && query['alpn']!.isNotEmpty) {
        tuic['alpn'] = query['alpn']!.split(',');
      }
      if (query.containsKey('sni')) {
        tuic['sni'] = query['sni'];
      }
      if (query['disable_sni'] == '1') {
        tuic['disable-sni'] = true;
      }
      if (query.containsKey('udp_relay_mode')) {
        tuic['udp-relay-mode'] = query['udp_relay_mode'];
      }

      return tuic;
    } catch (e) {
      return null;
    }
  }

  // Trojan parser
  static Map<String, dynamic>? _parseTrojan(String line, Map<String, int> names) {
    try {
      final uri = _safeParseUri(line);
      if (uri == null) return null;

      final query = uri.queryParameters;
      final name = _uniqueName(names, uri.fragment);

      final trojan = <String, dynamic>{
        'name': name,
        'type': 'trojan',
        'server': uri.host,
        'port': uri.hasPort ? uri.port : 443,
        'password': uri.userInfo,
        'udp': true,
        'skip-cert-verify': query['allowInsecure'] == '1',
      };

      if (query.containsKey('sni') && query['sni']!.isNotEmpty) {
        trojan['sni'] = query['sni'];
      }
      if (query.containsKey('alpn') && query['alpn']!.isNotEmpty) {
        trojan['alpn'] = query['alpn']!.split(',');
      }

      final network = query['type']?.toLowerCase() ?? '';
      if (network.isNotEmpty) {
        trojan['network'] = network;

        switch (network) {
          case 'ws':
          // CRITICAL: Headers must be a Map, not a string
            trojan['ws-opts'] = {
              'path': query['path'] ?? '/',
              'headers': <String, dynamic>{
                'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36',
              },
            };
            break;
          case 'grpc':
            trojan['grpc-opts'] = {
              'grpc-service-name': query['serviceName'] ?? '',
            };
            break;
        }
      }

      trojan['client-fingerprint'] = query['fp'] ?? 'chrome';

      return trojan;
    } catch (e) {
      return null;
    }
  }

  // VLess parser
  static Map<String, dynamic>? _parseVLess(String line, Map<String, int> names) {
    try {
      final uri = _safeParseUri(line);
      if (uri == null) return null;

      final query = uri.queryParameters;
      final name = _uniqueName(names, uri.fragment);

      final vless = <String, dynamic>{
        'name': name,
        'type': 'vless',
        'server': uri.host,
        'port': uri.hasPort ? uri.port : 443,
        'uuid': uri.userInfo,
        'udp': true,
      };

      if (query.containsKey('flow') && query['flow']!.isNotEmpty) {
        vless['flow'] = query['flow']!.toLowerCase();
      }
      if (query.containsKey('encryption')) {
        vless['encryption'] = query['encryption'];
      }
      if (query.containsKey('security')) {
        vless['tls'] = query['security'] == 'tls';
      }
      if (query.containsKey('sni')) {
        vless['sni'] = query['sni'];
      }
      if (query.containsKey('alpn') && query['alpn']!.isNotEmpty) {
        vless['alpn'] = query['alpn']!.split(',');
      }

      final network = query['type']?.toLowerCase() ?? 'tcp';
      if (network != 'tcp') {
        vless['network'] = network;

        switch (network) {
          case 'ws':
          // CRITICAL: Headers must be a proper Map
            final headers = <String, dynamic>{};
            if (query.containsKey('host') && query['host']!.isNotEmpty) {
              headers['Host'] = query['host'];
            }
            vless['ws-opts'] = {
              'path': query['path'] ?? '/',
              'headers': headers,
            };
            break;
          case 'grpc':
            vless['grpc-opts'] = {
              'grpc-service-name': query['serviceName'] ?? '',
            };
            break;
        }
      }

      return vless;
    } catch (e) {
      return null;
    }
  }

  // VMess parser
  static Map<String, dynamic>? _parseVMess(String line, Map<String, int> names) {
    try {
      final parts = line.split('://');
      if (parts.length < 2) return null;

      final body = parts.sublist(1).join('://');

      // Try V2RayN format first
      try {
        final decoded = base64.decode(body);
        final configString = utf8.decode(decoded);
        final config = json.decode(configString) as Map<String, dynamic>;

        return _parseVMessV2RayN(config, names);
      } catch (e) {
        // Try Xray VMessAEAD format
        return _parseVMessAEAD(line, names);
      }
    } catch (e) {
      return null;
    }
  }

  // VMess V2RayN format parser - FIXED HEADERS
  static Map<String, dynamic>? _parseVMessV2RayN(Map<String, dynamic> config, Map<String, int> names) {
    try {
      final tempName = config['ps'] as String?;
      if (tempName == null || tempName.isEmpty) return null;

      final name = _uniqueName(names, tempName);

      final vmess = <String, dynamic>{
        'name': name,
        'type': 'vmess',
        'server': config['add'],
        'port': config['port'],
        'uuid': config['id'],
        'alterId': config['aid'] ?? 0,
        'udp': true,
        'xudp': true,
        'tls': false,
        'skip-cert-verify': false,
        'cipher': config['scy'] ?? 'auto',
      };

      if (config.containsKey('sni') && config['sni'].toString().isNotEmpty) {
        vmess['servername'] = config['sni'];
      }

      var network = (config['net'] as String? ?? 'tcp').toLowerCase();
      if (config['type'] == 'http') {
        network = 'http';
      } else if (network == 'http') {
        network = 'h2';
      }

      if (network != 'tcp') {
        vmess['network'] = network;
      }

      final tls = (config['tls'] as String? ?? '').toLowerCase();
      if (tls.contains('tls')) {
        vmess['tls'] = true;
        if (config.containsKey('alpn') && config['alpn'].toString().isNotEmpty) {
          vmess['alpn'] = config['alpn'].toString().split(',');
        }
      }

      // CRITICAL FIX: Handle network-specific options with proper Map headers
      switch (network) {
        case 'http':
          final headers = <String, dynamic>{};
          if (config.containsKey('host') && config['host'].toString().isNotEmpty) {
            headers['Host'] = [config['host']];
          }
          vmess['http-opts'] = {
            'path': config.containsKey('path') && config['path'].toString().isNotEmpty
                ? [config['path']]
                : ['/'],
            'headers': headers,
          };
          break;

        case 'h2':
          final headers = <String, dynamic>{};
          if (config.containsKey('host') && config['host'].toString().isNotEmpty) {
            headers['Host'] = [config['host']];
          }
          vmess['h2-opts'] = {
            'path': config['path'] ?? '/',
            'headers': headers,
          };
          break;

        case 'ws':
        case 'httpupgrade':
        // CRITICAL: Create headers as proper Map, NOT string
          final headers = <String, dynamic>{};
          if (config.containsKey('host') && config['host'].toString().isNotEmpty) {
            headers['Host'] = config['host'];  // String value, not array
          }

          vmess['ws-opts'] = {
            'path': config['path'] ?? '/',
            'headers': headers,  // Always a Map
          };
          break;

        case 'grpc':
          vmess['grpc-opts'] = {
            'grpc-service-name': config['path'] ?? '',
          };
          break;
      }

      return vmess;
    } catch (e) {
      return null;
    }
  }

  // VMess AEAD format parser - FIXED HEADERS
  static Map<String, dynamic>? _parseVMessAEAD(String line, Map<String, int> names) {
    try {
      final uri = _safeParseUri(line);
      if (uri == null) return null;

      final query = uri.queryParameters;
      final name = _uniqueName(names, uri.fragment);

      final vmess = <String, dynamic>{
        'name': name,
        'type': 'vmess',
        'server': uri.host,
        'port': uri.hasPort ? uri.port : 443,
        'uuid': uri.userInfo,
        'alterId': 0,
        'cipher': query['encryption'] ?? 'auto',
        'udp': true,
      };

      final network = query['type']?.toLowerCase() ?? 'tcp';
      if (network != 'tcp') {
        vmess['network'] = network;

        switch (network) {
          case 'ws':
          // CRITICAL: Headers must be a Map
            final headers = <String, dynamic>{};
            if (query.containsKey('host') && query['host']!.isNotEmpty) {
              headers['Host'] = query['host'];
            }
            vmess['ws-opts'] = {
              'path': query['path'] ?? '/',
              'headers': headers,
            };
            break;
          case 'grpc':
            vmess['grpc-opts'] = {
              'grpc-service-name': query['serviceName'] ?? '',
            };
            break;
        }
      }

      return vmess;
    } catch (e) {
      return null;
    }
  }

  // Shadowsocks parser
  static Map<String, dynamic>? _parseSS(String line, Map<String, int> names) {
    try {
      final uri = _safeParseUri(line);
      if (uri == null) return null;

      final name = _uniqueName(names, uri.fragment);
      var port = uri.port;

      String cipher = '';
      String password = '';

      if (port == 0 || !uri.hasPort) {
        // Handle encoded format
        try {
          final decoded = base64.decode(uri.host);
          final decodedUri = _safeParseUri('ss://${utf8.decode(decoded)}');
          if (decodedUri == null) return null;

          cipher = decodedUri.userInfo.split(':')[0];
          password = decodedUri.userInfo.split(':').skip(1).join(':');
          port = decodedUri.port;
        } catch (e) {
          return null;
        }
      } else {
        if (uri.userInfo.contains(':')) {
          final parts = uri.userInfo.split(':');
          cipher = parts[0];
          password = parts.skip(1).join(':');
        } else {
          try {
            final decoded = base64.decode(uri.userInfo);
            final decodedStr = utf8.decode(decoded);
            if (decodedStr.contains(':')) {
              final parts = decodedStr.split(':');
              cipher = parts[0];
              password = parts.skip(1).join(':');
            }
          } catch (e) {
            return null;
          }
        }
      }

      if (cipher.isEmpty || password.isEmpty) return null;

      final ss = <String, dynamic>{
        'name': name,
        'type': 'ss',
        'server': uri.host,
        'port': port,
        'cipher': cipher,
        'password': password,
        'udp': true,
      };

      final query = uri.queryParameters;
      if (query['udp-over-tcp'] == 'true' || query['uot'] == '1') {
        ss['udp-over-tcp'] = true;
      }

      return ss;
    } catch (e) {
      return null;
    }
  }

  // SSR parser
  static Map<String, dynamic>? _parseSSR(String line, Map<String, int> names) {
    try {
      final parts = line.split('://');
      if (parts.length < 2) return null;

      final decoded = base64.decode(parts[1]);
      final decodedStr = utf8.decode(decoded);

      final mainParts = decodedStr.split('/?');
      if (mainParts.isEmpty) return null;

      final configParts = mainParts[0].split(':');
      if (configParts.length < 6) return null;

      final host = configParts[0];
      final port = configParts[1];
      final protocol = configParts[2];
      final method = configParts[3];
      final obfs = configParts[4];
      final passwordB64 = configParts[5];

      String password = '';
      try {
        password = utf8.decode(base64.decode(passwordB64));
      } catch (e) {
        password = passwordB64;
      }

      final query = mainParts.length > 1
          ? Uri.splitQueryString(mainParts[1])
          : <String, String>{};

      String remarks = 'SSR';
      if (query.containsKey('remarks')) {
        try {
          remarks = utf8.decode(base64.decode(query['remarks']!));
        } catch (e) {
          remarks = query['remarks']!;
        }
      }

      final name = _uniqueName(names, remarks);

      final ssr = <String, dynamic>{
        'name': name,
        'type': 'ssr',
        'server': host,
        'port': port,
        'cipher': method,
        'password': password,
        'obfs': obfs,
        'protocol': protocol,
        'udp': true,
      };

      if (query.containsKey('obfsparam')) {
        try {
          ssr['obfs-param'] = utf8.decode(base64.decode(query['obfsparam']!));
        } catch (e) {
          ssr['obfs-param'] = query['obfsparam'];
        }
      }

      if (query.containsKey('protoparam')) {
        try {
          ssr['protocol-param'] = utf8.decode(base64.decode(query['protoparam']!));
        } catch (e) {
          ssr['protocol-param'] = query['protoparam'];
        }
      }

      return ssr;
    } catch (e) {
      return null;
    }
  }

  // Socks/HTTP parser
  static Map<String, dynamic>? _parseSocksHttp(String line, Map<String, int> names) {
    try {
      final uri = _safeParseUri(line);
      if (uri == null) return null;

      final server = uri.host;
      if (server.isEmpty) return null;

      final port = uri.hasPort ? uri.port : 1080;

      var remarks = uri.fragment;
      if (remarks.isEmpty) {
        remarks = '$server:$port';
      }

      final name = _uniqueName(names, remarks);

      var username = '';
      var password = '';

      if (uri.userInfo.isNotEmpty) {
        try {
          final decoded = base64.decode(uri.userInfo);
          final decodedStr = utf8.decode(decoded);
          if (decodedStr.contains(':')) {
            final parts = decodedStr.split(':');
            username = parts[0];
            password = parts.skip(1).join(':');
          }
        } catch (e) {
          if (uri.userInfo.contains(':')) {
            final parts = uri.userInfo.split(':');
            username = parts[0];
            password = parts.skip(1).join(':');
          }
        }
      }

      final scheme = uri.scheme.toLowerCase();
      final type = (scheme == 'socks' || scheme == 'socks5' || scheme == 'socks5h')
          ? 'socks5'
          : 'http';

      final proxy = <String, dynamic>{
        'name': name,
        'type': type,
        'server': server,
        'port': port,
        'udp': true,
      };

      if (username.isNotEmpty) proxy['username'] = username;
      if (password.isNotEmpty) proxy['password'] = password;

      proxy['skip-cert-verify'] = true;

      if (scheme == 'https') {
        proxy['tls'] = true;
      }

      return proxy;
    } catch (e) {
      return null;
    }
  }
}