import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'iap_service.dart';

// Build-time override for the ads-removed state. When provided via
// --dart-define=ADS_REMOVED_OVERRIDE=true|false this value will be respected
// unconditionally by the IAP service adsRemoved getter.
const String _kAdsRemovedOverrideRaw = String.fromEnvironment(
  'ADS_REMOVED_OVERRIDE',
);

bool? _parseOverrideBool(String raw) {
  final s = raw.trim().toLowerCase();
  if (s.isEmpty) return null;
  if (s == 'true' || s == '1' || s == 'yes') return true;
  if (s == 'false' || s == '0' || s == 'no') return false;
  return null;
}

bool? _forcedAdsRemoved() {
  if (_kAdsRemovedOverrideRaw.isEmpty) return null;
  return _parseOverrideBool(_kAdsRemovedOverrideRaw);
}

class IosIapServiceImpl implements IapService {
  static const String productIdRemoveAds = 'dev.golfapp.swinggroove.remove_ads';
  static const String prefsKeyAdsRemoved = 'ads_removed';

  final InAppPurchase _iap = InAppPurchase.instance;
  StreamSubscription<List<PurchaseDetails>>? _sub;

  bool _available = false;
  bool _adsRemoved = false;

  @override
  bool get adsRemoved {
    final forced = _forcedAdsRemoved();
    if (forced != null) return forced;
    return _adsRemoved;
  }

  @override
  Future<void> init() async {
    _available = await _iap.isAvailable();
    final prefs = await SharedPreferences.getInstance();
    _adsRemoved = prefs.getBool(prefsKeyAdsRemoved) ?? false;

    final forced = _forcedAdsRemoved();
    if (forced != null && kDebugMode) {
      debugPrint('IAP: ADS_REMOVED_OVERRIDE=$forced (forcing adsRemoved)');
    }

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
    if (resp.productDetails.isEmpty) return null;
    for (final p in resp.productDetails) {
      if (p.id == productIdRemoveAds) return p;
    }
    // Fallback: return first product if exact ID not found
    return resp.productDetails.first;
  }

  @override
  Future<bool> buyRemoveAds(ProductDetails product) async {
    if (!_available) {
      if (kDebugMode) {
        debugPrint('IAP: Store not available; cannot start purchase.');
      }
      return false;
    }
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
