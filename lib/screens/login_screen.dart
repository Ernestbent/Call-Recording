import 'package:calls_recording/screens/home_screen.dart';
import 'package:calls_recording/services/customer_call_store.dart';
import 'package:calls_recording/services/erpnext_auth_service.dart';
import 'package:calls_recording/services/secure_session_storage.dart';
import 'package:calls_recording/theme/app_theme.dart';
import 'package:calls_recording/widgets/company_logo.dart';
import 'package:flutter/material.dart';

class LoginScreen extends StatefulWidget {
  final CustomerCallStore appState;
  final ErpNextAuthenticator? erpNextAuthenticator;
  final SessionStorage? sessionStorage;

  const LoginScreen({
    super.key,
    required this.appState,
    this.erpNextAuthenticator,
    this.sessionStorage,
  });

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();

  late final ErpNextAuthenticator _erpNextAuthenticator;
  late final SessionStorage _sessionStorage;

  bool _rememberMe = true;
  bool _obscurePassword = true;
  bool _isLoggingIn = false;
  String? _loginError;

  bool get _isBusy => _isLoggingIn;

  @override
  void initState() {
    super.initState();
    _erpNextAuthenticator = widget.erpNextAuthenticator ?? ErpNextAuthService();
    _sessionStorage = widget.sessionStorage ?? SecureSessionStorage();
  }

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _login() async {
    FocusScope.of(context).unfocus();
    if (!(_formKey.currentState?.validate() ?? false)) return;

    setState(() {
      _isLoggingIn = true;
      _loginError = null;
    });

    try {
      final session = await _erpNextAuthenticator.login(
        username: _emailController.text,
        password: _passwordController.text,
      );

      if (_rememberMe) {
        await _sessionStorage.save(session);
      } else {
        await _sessionStorage.clear();
      }

      await widget.appState.loadDraftPaymentCustomers(session);

      if (!mounted) return;
      _openHome();
    } on ErpNextAuthException catch (error) {
      if (!mounted) return;
      setState(() {
        _loginError = error.message;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loginError =
            'Login succeeded, but the session could not be saved securely.';
      });
    } finally {
      if (mounted) {
        setState(() {
          _isLoggingIn = false;
        });
      }
    }
  }

  void _showMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  void _openHome() {
    Navigator.of(context).pushReplacement(
      MaterialPageRoute<void>(
        builder: (context) => HomeScreen(appState: widget.appState),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 430),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const SizedBox(height: 12),
                    const Center(
                      child: CompanyLogo(
                        width: 180,
                        height: 110,
                        borderRadius: 16,
                      ),
                    ),
                    const SizedBox(height: 30),
                    const Text(
                      'Welcome Back',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: AppColors.ink,
                        fontSize: 30,
                        fontWeight: FontWeight.w400,
                        letterSpacing: -0.6,
                      ),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'Login to continue to your account',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: AppColors.muted, fontSize: 16),
                    ),
                    const SizedBox(height: 36),
                    TextFormField(
                      key: const Key('login-email-field'),
                      controller: _emailController,
                      keyboardType: TextInputType.emailAddress,
                      textInputAction: TextInputAction.next,
                      autofillHints: const [
                        AutofillHints.username,
                        AutofillHints.email,
                      ],
                      decoration: const InputDecoration(
                        hintText: 'Email or Username',
                        prefixIcon: Icon(Icons.mail_outline_rounded),
                      ),
                      validator: (value) {
                        if (value == null || value.trim().isEmpty) {
                          return 'Enter your email or username';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      key: const Key('login-password-field'),
                      controller: _passwordController,
                      obscureText: _obscurePassword,
                      textInputAction: TextInputAction.done,
                      autofillHints: const [AutofillHints.password],
                      onFieldSubmitted: (_) {
                        if (!_isBusy) _login();
                      },
                      decoration: InputDecoration(
                        hintText: 'Password',
                        prefixIcon: const Icon(Icons.lock_outline_rounded),
                        suffixIcon: IconButton(
                          tooltip: _obscurePassword
                              ? 'Show password'
                              : 'Hide password',
                          onPressed: () {
                            setState(() {
                              _obscurePassword = !_obscurePassword;
                            });
                          },
                          icon: Icon(
                            _obscurePassword
                                ? Icons.visibility_outlined
                                : Icons.visibility_off_outlined,
                          ),
                        ),
                      ),
                      validator: (value) {
                        if (value == null || value.isEmpty) {
                          return 'Enter your password';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Checkbox(
                          value: _rememberMe,
                          activeColor: AppColors.primary,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(4),
                          ),
                          onChanged: (value) {
                            setState(() {
                              _rememberMe = value ?? false;
                            });
                          },
                        ),
                        const Expanded(
                          child: Text(
                            'Remember me',
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: AppColors.ink,
                              fontSize: 14,
                            ),
                          ),
                        ),
                        TextButton(
                          onPressed: () {
                            _showMessage(
                              'Please contact your administrator to reset '
                              'your password.',
                            );
                          },
                          child: const Text('Forgot Password?'),
                        ),
                      ],
                    ),
                    if (_loginError != null) ...[
                      Container(
                        key: const Key('login-error'),
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: const Color(0xFFFFECEA),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Icon(
                              Icons.error_outline_rounded,
                              color: Color(0xFFB3261E),
                              size: 20,
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                _loginError!,
                                style: const TextStyle(
                                  color: Color(0xFFB3261E),
                                  fontSize: 13,
                                  height: 1.3,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 14),
                    ],
                    const SizedBox(height: 20),
                    SizedBox(
                      height: 56,
                      child: FilledButton(
                        key: const Key('login-button'),
                        onPressed: _isBusy ? null : _login,
                        child: _isLoggingIn
                            ? const SizedBox(
                                width: 22,
                                height: 22,
                                child: CircularProgressIndicator(
                                  color: Colors.white,
                                  strokeWidth: 2.5,
                                ),
                              )
                            : const Text(
                                'Login',
                                style: TextStyle(fontSize: 17),
                              ),
                      ),
                    ),
                    const SizedBox(height: 12),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
