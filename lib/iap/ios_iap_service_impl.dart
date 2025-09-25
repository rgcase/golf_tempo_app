import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'iap_service.dart';

class IosIapServiceImpl implements IapService {
  static const String productIdRemoveAds = 'dev.golfapp.swinggroove.remove_ads';
  static const String prefsKeyAdsRemoved = 'ads_removed';

  final InAppPurchase _iap = InAppPurchase.instance;
  StreamSubscription<List<PurchaseDetails>>? _sub;

  bool _available = false;
  bool _adsRemoved = false;

  @override
  bool get adsRemoved => _adsRemoved;

  @override
  Future<void> init() async {
    _available = await _iap.isAvailable();
    final prefs = await SharedPreferences.getInstance();
    _adsRemoved = prefs.getBool(prefsKeyAdsRemoved) ?? false;

    _sub = _iap.purchaseStream.listen(
      _onPurchases,
      onDone: () => _sub?.cancel(),
      onError: (Object err) {},
    );
  }

  @override
  Future<void> dispose() async {
    await _sub?.cancel();
  }

  @override
  Future<ProductDetails?> loadRemoveAdsProduct() async {
    if (!_available) return null;
    final resp = await _iap.queryProductDetails({productIdRemoveAds});
    if (resp.error != null) {
      if (kDebugMode) {
        debugPrint('IAP query error: ${resp.error}');
      }
      return null;
    }
    return resp.productDetails.firstWhere(
      (p) => p.id == productIdRemoveAds,
      orElse: () =>
          (resp.productDetails.isEmpty ? null : resp.productDetails.first)!,
    );
  }

  @override
  Future<bool> buyRemoveAds(ProductDetails product) async {
    final param = PurchaseParam(productDetails: product);
    return _iap.buyNonConsumable(purchaseParam: param);
  }

  @override
  Future<void> restore() async {
    await _iap.restorePurchases();
  }

  Future<void> _onPurchases(List<PurchaseDetails> purchases) async {
    for (final p in purchases) {
      switch (p.status) {
        case PurchaseStatus.pending:
          break;
        case PurchaseStatus.purchased:
        case PurchaseStatus.restored:
          await _verifyAndComplete(p, grant: true);
          break;
        case PurchaseStatus.error:
          if (kDebugMode) {
            debugPrint('IAP error: ${p.error}');
          }
          await _completeIfNeeded(p);
          break;
        case PurchaseStatus.canceled:
          await _completeIfNeeded(p);
          break;
      }
    }
  }

  Future<void> _verifyAndComplete(
    PurchaseDetails p, {
    required bool grant,
  }) async {
    if (grant && p.productID == productIdRemoveAds) {
      _adsRemoved = true;
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(prefsKeyAdsRemoved, true);
    }
    await _completeIfNeeded(p);
  }

  Future<void> _completeIfNeeded(PurchaseDetails p) async {
    if (p.pendingCompletePurchase) {
      await _iap.completePurchase(p);
    }
  }
}

