import 'menu_item.dart';

class CartItem {
  final MenuItem menuItem;
  final int quantity;
  final String? observations;
  final List<String> extras; // Nomes dos extras selecionados
  final double extrasPrice; // Preco total dos extras

  CartItem({
    required this.menuItem,
    required this.quantity,
    this.observations,
    this.extras = const [],
    this.extrasPrice = 0.0,
  });

  double get subtotal {
    return (menuItem.price + extrasPrice) * quantity;
  }

  CartItem copyWith({
    MenuItem? menuItem,
    int? quantity,
    String? observations,
    List<String>? extras,
    double? extrasPrice,
  }) {
    return CartItem(
      menuItem: menuItem ?? this.menuItem,
      quantity: quantity ?? this.quantity,
      observations: observations ?? this.observations,
      extras: extras ?? this.extras,
      extrasPrice: extrasPrice ?? this.extrasPrice,
    );
  }
}





