import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';

void main() => runApp(const MyApp());

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'My WE Studio',
      theme: ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: const Color(0xFF0F172A),
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF00C853),
          brightness: Brightness.dark,
        ),
      ),
      home: const WEAuthScreen(),
    );
  }
}

class WEAuthScreen extends StatefulWidget {
  const WEAuthScreen({super.key});

  @override
  State<WEAuthScreen> createState() => _WEAuthScreenState();
}

class _WEAuthScreenState extends State<WEAuthScreen> {
  final TextEditingController _phoneController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  
  bool _isLoading = false;
  String? _errorMessage;
  Map<String, dynamic>? _profileData;

  Map<String, String> _analyzeNationalId(String nid) {
    if (nid.length != 14) return {};
    try {
      String centuryCode = nid[0];
      int year2 = int.parse(nid.substring(1, 3));
      int month = int.parse(nid.substring(3, 5));
      int day = int.parse(nid.substring(5, 7));
      String govCode = nid.substring(7, 9);
      int genderDigit = int.parse(nid[12]);

      int year = (centuryCode == "2" ? 1900 : centuryCode == "3" ? 2000 : 1800) + year2;

      Map<String, String> governorates = {
        "01": "القاهرة", "02": "الإسكندرية", "03": "بورسعيد", "04": "السويس", "11": "دمياط",
        "12": "الدقهلية", "13": "الشرقية", "14": "القليوبية", "15": "كفر الشيخ", "16": "الغربية",
        "17": "المنوفية", "18": "البحيرة", "19": "الإسماعيلية", "21": "الجيزة", "22": "بني سويف",
        "23": "الفيوم", "24": "المنيا", "25": "أسيوط", "26": "سوهاج", "27": "قنا", "28": "أسوان",
        "29": "الأقصر", "31": "البحر الأحمر", "32": "الوادي الجديد", "33": "مطروح",
        "34": "شمال سيناء", "35": "جنوب سيناء", "88": "خارج الجمهورية"
      };

      return {
        "birthday": "$year-$month-$day",
        "governorate": governorates[govCode] ?? "غير معروف",
        "gender": genderDigit % 2 == 1 ? "ذكر" : "أنثى",
      };
    } catch (_) {
      return {};
    }
  }

  Future<void> _loginAndFetchData() async {
    final phone = _phoneController.text.trim();
    if (phone.isEmpty) {
      setState(() => _errorMessage = "يرجى ادخال رقم الهاتف");
      return;
    }

    FocusScope.of(context).unfocus();
    setState(() {
      _isLoading = true;
      _errorMessage = null;
      _profileData = null;
    });

    try {
      final client = http.Client();
      
      final captchaRes = await client.post(
        Uri.parse("https://captcha.te.eg/api/Captcha/GenerateCaptcha"),
        headers: {"Content-Type": "application/json; charset=utf-8"},
        body: jsonEncode({"merchantName": "E-Care", "serviceName": "Login", "identifier": phone}),
      );

      final captchaData = jsonDecode(captchaRes.body);
      final imgCacheKey = captchaData["token"] ?? "";

      if (imgCacheKey.isEmpty) {
        throw "فشل توليد الكابتشا من السيرفر";
      }

      final deviceId = "a1b2c3d4e5f67890";
      final authRes = await client.post(
        Uri.parse("https://app-my.te.eg/echannel/service/besapp/base/rest/busiservice/v1/auth/userAuthenticate"),
        headers: {
          "Content-Type": "application/json",
          "systemtype": "android",
          "deviceid": deviceId,
          "appversionno": "122",
        },
        body: jsonEncode({
          "acctId": phone.replaceFirst(RegExp(r'^0'), ''),
          "password": _passwordController.text.trim(),
          "appLocale": "ar-EG",
          "isSelfcare": "Y",
          "isMobile": "Y",
          "imgCacheKey": imgCacheKey,
          "isConvergent": "0"
        }),
      );

      final result = jsonDecode(authRes.body);
      final header = result["header"] ?? {};
      
      if (header["retCode"] != "0") {
        throw header["errorMsg"] ?? "فشل تسجيل الدخول، تأكد من البيانات";
      }

      final body = result["body"] ?? {};
      final customer = body["customer"] ?? {};
      final account = body["account"] ?? {};
      final subscriber = body["subscriber"] ?? {};
      final individual = customer["individualInfo"] ?? {};
      final uToken = body["utoken"] ?? "";
      final loginToken = body["token"] ?? "";
      final refreshToken = body["refresh_token"] ?? "";

      // تصحيح نوع البيانات ليطابق Map<String, String> بدقة تامة
      final Map<String, String> commonHeaders = {
        "Content-Type": "application/json",
        "csrftoken": loginToken.toString(),
        "indiv_login_token": uToken.toString(),
        "refresh_token": refreshToken.toString(),
        "deviceid": deviceId,
        "systemtype": "android",
      };

      String fullNationalId = "";
      try {
        final nidRes = await client.post(
          Uri.parse("https://app-my.te.eg/echannel/service/besapp/base/rest/busiservice/cz/v1/customer/validateNationalIDType"),
          headers: commonHeaders,
          body: jsonEncode({"nationalId": ""}),
        );
        fullNationalId = jsonDecode(nidRes.body)["body"]?["nationalId"] ?? "";
      } catch (_) {}

      setState(() {
        _profileData = {
          "custName": customer["custName"] ?? "غير معروف",
          "gender": individual["gender"] == "1" ? "ذكر" : "أنثى",
          "custType": customer["custType"] == "1" ? "فردي" : "شركة",
          "servNumber": subscriber["servNumber"] ?? phone,
          "state": subscriber["state"] == "2" ? "نشط" : "موقوف",
          "paymentType": subscriber["paymentType"] == "1" ? "فاتورة" : "مدفوع مسبقاً",
          "acctId": account["acctId"] ?? "-",
          "nationalId": fullNationalId,
          "nidAnalysis": _analyzeNationalId(fullNationalId),
        };
        _isLoading = false;
      });

    } catch (e) {
      setState(() {
        _isLoading = false;
        _errorMessage = "خطأ: ${e.toString()}";
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('My WE Studio', style: TextStyle(fontWeight: FontWeight.bold)),
        centerTitle: true,
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: const Color(0xFF1E293B),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: const Color(0xFF334155)),
                ),
                child: Column(
                  children: [
                    TextField(
                      controller: _phoneController,
                      keyboardType: TextInputType.phone,
                      decoration: InputDecoration(
                        labelText: 'رقم الخط (اتصالات/WE)',
                        prefixIcon: const Icon(Icons.phone, color: Color(0xFF00C853)),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                    ),
                    const SizedBox(height: 14),
                    TextField(
                      controller: _passwordController,
                      obscureText: true,
                      decoration: InputDecoration(
                        labelText: 'كلمة المرور',
                        prefixIcon: const Icon(Icons.lock, color: Color(0xFF00C853)),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                    ),
                    const SizedBox(height: 18),
                    SizedBox(
                      width: double.infinity,
                      height: 50,
                      child: ElevatedButton(
                        onPressed: _isLoading ? null : _loginAndFetchData,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF00C853),
                          foregroundColor: Colors.black,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                        child: _isLoading
                            ? const CircularProgressIndicator(color: Colors.black)
                            : const Text('تسجيل الدخول وجلب البيانات', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                      ),
                    ),
                    if (_errorMessage != null) ...[
                      const SizedBox(height: 12),
                      Text(_errorMessage!, style: const TextStyle(color: Colors.redAccent, fontSize: 13), textAlign: TextAlign.center),
                    ]
                  ],
                ),
              ),
              const SizedBox(height: 24),
              if (_profileData != null) ...[
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: const Color(0xFF131C31),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: const Color(0xFF00C853).withOpacity(0.4)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Row(
                        children: [
                          Icon(Icons.check_circle, color: Color(0xFF00C853)),
                          SizedBox(width: 8),
                          Text('بيانات العميل المستخرجة', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                        ],
                      ),
                      const Divider(height: 24, color: Colors.grey),
                      _buildInfoRow('اسم العميل', _profileData!['custName']),
                      _buildInfoRow('رقم الخط', _profileData!['servNumber']),
                      _buildInfoRow('نوع الدفع', _profileData!['paymentType']),
                      _buildInfoRow('حالة الخط', _profileData!['state']),
                      _buildInfoRow('الرقم القومي', _profileData!['nationalId'].isEmpty ? 'غير متوفر' : _profileData!['nationalId']),
                      if (_profileData!['nidAnalysis'].isNotEmpty) ...[
                        const SizedBox(height: 8),
                        _buildInfoRow('تاريخ الميلاد', _profileData!['nidAnalysis']['birthday']),
                        _buildInfoRow('المحافظة', _profileData!['nidAnalysis']['governorate']),
                        _buildInfoRow('الجنس', _profileData!['nidAnalysis']['gender']),
                      ],
                    ],
                  ),
                ),
              ]
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildInfoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(color: Colors.grey, fontSize: 14)),
          Text(value, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14)),
        ],
      ),
    );
  }
}