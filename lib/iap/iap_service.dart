import 'package:in_app_purchase/in_app_purchase.dart';

abstract class IapService {
  bool get adsRemoved;

  Future<void> init();

  Future<void> dispose();

  Future<ProductDetails?> loadRemoveAdsProduct();

  Future<bool> buyRemoveAds(ProductDetails product);

  Future<void> restore();
}
