import 'dart:async';
import 'dart:io';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lazerpay_flutter/src/model/lazerpay_data.dart';
import 'package:lazerpay_flutter/src/model/lazerpay_event_model.dart';
import 'package:lazerpay_flutter/src/raw/lazer_html.dart';
import 'package:lazerpay_flutter/src/utils/functions.dart';
import 'package:modal_bottom_sheet/modal_bottom_sheet.dart';
import 'package:lazerpay_flutter/src/const/const.dart';
import 'package:lazerpay_flutter/src/widgets/lazerpay_loader.dart';
import 'package:webview_flutter/webview_flutter.dart';

import 'package:lazerpay_flutter/src/utils/extensions.dart';
import 'package:lazerpay_flutter/src/views/lazerpay_error_view.dart';

class LazerPaySendView extends StatefulWidget {
  /// Public Key from your https://app.withLazerPay.com/apps
  final LazerPayData data;

  /// Success callback
  final ValueChanged<dynamic>? onSuccess;

  /// Error callback<
  final ValueChanged<dynamic>? onError;

  /// LazerPay popup Close callback
  final VoidCallback? onClosed;

  /// Error Widget will show if loading fails
  final Widget? errorWidget;

  /// Show LazerPaySendView Logs
  final bool showLogs;

  /// Toggle dismissible mode
  final bool isDismissible;

  const LazerPaySendView({
    Key? key,
    required this.data,
    this.errorWidget,
    this.onSuccess,
    this.onClosed,
    this.onError,
    this.showLogs = false,
    this.isDismissible = true,
  }) : super(key: key);

  /// Show Dialog with a custom child
  Future show(BuildContext context) => showMaterialModalBottomSheet<void>(
        backgroundColor: Colors.white,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.only(
            topLeft: Radius.circular(10),
            topRight: Radius.circular(10),
          ),
        ),
        isDismissible: isDismissible,
        context: context,
        builder: (context) => ClipRRect(
          borderRadius: const BorderRadius.only(
            topLeft: Radius.circular(10),
            topRight: Radius.circular(10),
          ),
          child: SizedBox(
            height: MediaQuery.of(context).size.height * 0.9,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Center(
                  child: SizedBox(
                    height: context.screenHeight(.9),
                    child: LazerPaySendView(
                      data: data,
                      onClosed: onClosed,
                      onSuccess: onSuccess,
                      onError: onError,
                      showLogs: showLogs,
                      errorWidget: errorWidget,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      );

  @override
  _LazerPaySendViewState createState() => _LazerPaySendViewState();
}

class _LazerPaySendViewState extends State<LazerPaySendView> {
  final _controller = Completer<WebViewController>();
  Future<WebViewController> get _webViewController => _controller.future;

  bool _isLoading = true;
  bool get isLoading => _isLoading;
  set isLoading(bool val) {
    _isLoading = val;
    setState(() {});
  }

  bool _hasError = false;
  bool get hasError => _hasError;
  set hasError(bool val) {
    _hasError = val;
    setState(() {});
  }

  int? _loadingPercent;
  int? get loadingPercent => _loadingPercent;
  set loadingPercent(int? val) {
    _loadingPercent = val;
    setState(() {});
  }

  @override
  void initState() {
    super.initState();
    _handleInit();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: FutureBuilder<ConnectivityResult>(
        future: Connectivity().checkConnectivity(),
        builder: (context, snapshot) {
          /// Show error view
          if (hasError == true) {
            return Center(
              child: widget.errorWidget ??
                  LazerPayErrorView(
                    onClosed: widget.onClosed,
                    reload: () async {
                      setState(() {});
                      await (await _webViewController).reload();
                    },
                  ),
            );
          }

          if (snapshot.hasData == true &&
              snapshot.data != ConnectivityResult.none) {
            final createUrl = LazerPayHtml.buildLazerPayHtml(
              widget.data,
            );
            return Stack(
              alignment: Alignment.center,
              children: [
                if (isLoading == true) ...[
                  const LazerPayLoader(),
                ],

                /// LazerPay Webview
                AnimatedOpacity(
                  duration: const Duration(milliseconds: 400),
                  opacity: isLoading == true && _loadingPercent != 100 ? 0 : 1,
                  child: WebView(
                    initialUrl: createUrl.toString(),
                    onWebViewCreated: _controller.complete,
                    javascriptChannels: _thelazerpayJavascriptChannel,
                    javascriptMode: JavascriptMode.unrestricted,
                    zoomEnabled: false,
                    debuggingEnabled: true,
                    onPageStarted: (_) async {
                      isLoading = true;
                    },
                    onWebResourceError: (e) {
                      if (widget.showLogs) LazerPayFunctions.log(e.toString());
                    },
                    onProgress: (v) {
                      loadingPercent = v;
                    },
                    onPageFinished: (_) async {
                      isLoading = false;
                    },
                    navigationDelegate: _handleNavigationInterceptor,
                  ),
                ),
              ],
            );
          } else {
            return const Center(child: CupertinoActivityIndicator());
          }
        },
      ),
    );
  }

  /// Javascript channel for events sent by LazerPay
  Set<JavascriptChannel> get _thelazerpayJavascriptChannel => {
        JavascriptChannel(
          name: 'LazerPayClientInterface',
          onMessageReceived: (JavascriptMessage data) {
            try {
              if (widget.showLogs)
                LazerPayFunctions.log('Event: -> ${data.message}');
              _handleResponse(data.message);
            } on Exception {
              if (mounted && widget.onClosed != null) {
                widget.onClosed!();
              }
            } catch (e) {
              if (widget.showLogs) LazerPayFunctions.log(e.toString());
            }
          },
        )
      };

  /// Parse event from javascript channel
  void _handleResponse(String res) async {
    try {
      final data = LazerPayEventModel.fromJson(res);
      switch (data.type) {
        case ON_SUCCESS:
          if (widget.onSuccess != null) {
            widget.onSuccess!(
              res,
            );
          }
          return;
        case ON_CLOSE:
          if (mounted && widget.onClosed != null) {
            widget.onClosed!();
          }
          return;
        default:
          if (mounted && widget.onError != null) widget.onError!(res);
          return;
      }
    } catch (e) {
      if (widget.showLogs == true) LazerPayFunctions.log(e.toString());
    }
  }

  /// Handle WebView initialization
  void _handleInit() async {
    await SystemChannels.textInput.invokeMethod<String>('TextInput.hide');
    if (Platform.isAndroid) WebView.platform = SurfaceAndroidWebView();
  }

  NavigationDecision _handleNavigationInterceptor(NavigationRequest request) {
    /* if (request.url.toLowerCase().contains('chain.thelazerpay.co')) {
      // Navigate to all urls contianing LazerPay */
    return NavigationDecision.navigate;
    /* } else {
      // Block all navigations outside LazerPay
      return NavigationDecision.prevent;
    } */
  }
}
