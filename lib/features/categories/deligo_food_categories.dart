import 'package:flutter/material.dart';

class DeligoFoodCategory {
  final String id;
  final String label;
  final IconData icon;
  final Color color;
  final Set<String> aliases;

  const DeligoFoodCategory({
    required this.id,
    required this.label,
    required this.icon,
    required this.color,
    required this.aliases,
  });
}

class DeligoSmartCategory {
  final String id;
  final String label;
  final IconData icon;
  final Color color;

  const DeligoSmartCategory({
    required this.id,
    required this.label,
    required this.icon,
    required this.color,
  });
}

class DeligoFoodCategories {
  static const all = DeligoFoodCategory(
    id: 'all',
    label: 'Todos',
    icon: Icons.grid_view_rounded,
    color: Color(0xFF5B6472),
    aliases: {},
  );

  static const list = <DeligoFoodCategory>[
    DeligoFoodCategory(
      id: 'local_traditional',
      label: 'Local',
      icon: Icons.rice_bowl_rounded,
      color: Color(0xFFC96A2B),
      aliases: {
        'comida mocambicana',
        'pratos tradicionais',
        'xima',
        'xima & acompanhamentos',
        'caril',
        'caril & molhos',
        'pratos com coco',
        'pratos com coco / amendoim',
        'matapa',
        'tradicional',
        'local',
        'especialidades',
      },
    ),
    DeligoFoodCategory(
      id: 'meat_protein',
      label: 'Carnes',
      icon: Icons.outdoor_grill_rounded,
      color: Color(0xFFBF3F34),
      aliases: {
        'frango',
        'carne bovina',
        'porco',
        'cabrito',
        'grelhados',
        'churrasco',
        'espetadas',
        'proteinas',
        'carnes',
      },
    ),
    DeligoFoodCategory(
      id: 'seafood_fish',
      label: 'Mariscos',
      icon: Icons.set_meal_rounded,
      color: Color(0xFF2F8FA3),
      aliases: {
        'mariscos',
        'camarao',
        'lagosta',
        'caranguejo',
        'peixe grelhado',
        'peixe frito',
        'peixe',
      },
    ),
    DeligoFoodCategory(
      id: 'fast_food',
      label: 'Fast Food',
      icon: Icons.lunch_dining_rounded,
      color: Color(0xFFE86A33),
      aliases: {
        'fast food',
        'hamburgueres',
        'hamburguer',
        'pizzas',
        'pizza',
        'cachorros',
        'hot dog',
        'sanduiches',
        'shawarma',
        'wraps',
        'shawarma / wraps',
        'batatas fritas',
      },
    ),
    DeligoFoodCategory(
      id: 'international',
      label: 'Internacional',
      icon: Icons.public_rounded,
      color: Color(0xFF6B59CC),
      aliases: {
        'italiana',
        'chinesa',
        'indiana',
        'japonesa',
        'portuguesa',
        'brasileira',
        'africana',
        'internacional',
      },
    ),
    DeligoFoodCategory(
      id: 'healthy_diet',
      label: 'Saudavel',
      icon: Icons.eco_rounded,
      color: Color(0xFF3F9D57),
      aliases: {
        'saudavel',
        'fitness',
        'vegetariano',
        'vegano',
        'low carb',
        'sem gluten',
        'saudavel / light',
        'light',
      },
    ),
    DeligoFoodCategory(
      id: 'breakfast_snacks',
      label: 'Lanches',
      icon: Icons.breakfast_dining_rounded,
      color: Color(0xFFCE8E2D),
      aliases: {
        'pequeno-almoco',
        'pequeno-almoco / lanches',
        'lanches',
        'omeletes',
        'panquecas',
        'pao',
        'pao & torradas',
      },
    ),
    DeligoFoodCategory(
      id: 'soups_light',
      label: 'Sopas',
      icon: Icons.soup_kitchen_rounded,
      color: Color(0xFF4E8FAF),
      aliases: {
        'sopas',
        'caldos',
        'pratos leves',
      },
    ),
    DeligoFoodCategory(
      id: 'full_meals',
      label: 'Refeicoes',
      icon: Icons.dinner_dining_rounded,
      color: Color(0xFF8A5A3B),
      aliases: {
        'pratos do dia',
        'menu executivo',
        'combos refeicao',
        'pratos principais',
      },
    ),
    DeligoFoodCategory(
      id: 'family_groups',
      label: 'Familia',
      icon: Icons.groups_rounded,
      color: Color(0xFF5965C8),
      aliases: {
        'combos familiares',
        'partilha',
        'bandejas grandes',
        'familia',
      },
    ),
    DeligoFoodCategory(
      id: 'drinks',
      label: 'Bebidas',
      icon: Icons.local_drink_rounded,
      color: Color(0xFF2A9F84),
      aliases: {
        'bebidas',
        'refrigerantes',
        'sumos naturais',
        'smoothies',
        'agua',
        'cha gelado',
        'cervejas',
        'vinhos',
        'cocktails',
        'whisky',
        'gin',
        'vodka',
        'cafe',
        'cappuccino',
        'cha',
        'chocolate quente',
      },
    ),
    DeligoFoodCategory(
      id: 'desserts',
      label: 'Sobremesas',
      icon: Icons.icecream_rounded,
      color: Color(0xFFD35D91),
      aliases: {
        'sobremesas',
        'bolos',
        'gelados',
        'doces tradicionais',
        'pudins',
      },
    ),
  ];

  static const smart = <DeligoSmartCategory>[
    DeligoSmartCategory(
      id: 'popular',
      label: 'Mais vendidos',
      icon: Icons.local_fire_department_rounded,
      color: Color(0xFFE4572E),
    ),
    DeligoSmartCategory(
      id: 'recommended',
      label: 'Recomendados',
      icon: Icons.star_rounded,
      color: Color(0xFFE0A100),
    ),
    DeligoSmartCategory(
      id: 'new',
      label: 'Novos',
      icon: Icons.fiber_new_rounded,
      color: Color(0xFF2D8CFF),
    ),
    DeligoSmartCategory(
      id: 'promotions',
      label: 'Promocoes',
      icon: Icons.percent_rounded,
      color: Color(0xFF2FA36B),
    ),
    DeligoSmartCategory(
      id: 'fast_delivery',
      label: 'Entrega rapida',
      icon: Icons.bolt_rounded,
      color: Color(0xFF9C4DFF),
    ),
    DeligoSmartCategory(
      id: 'nearby',
      label: 'Perto de si',
      icon: Icons.near_me_rounded,
      color: Color(0xFF148F77),
    ),
    DeligoSmartCategory(
      id: 'budget',
      label: 'Economico',
      icon: Icons.savings_rounded,
      color: Color(0xFF5E9C36),
    ),
    DeligoSmartCategory(
      id: 'top_restaurants',
      label: 'Top restaurantes',
      icon: Icons.workspace_premium_rounded,
      color: Color(0xFFCC6F00),
    ),
  ];

  static String normalize(String value) {
    return value
        .toLowerCase()
        .trim()
        .replaceAll('&', ' ')
        .replaceAll('/', ' ')
        .replaceAll('-', ' ')
        .replaceAll(RegExp(r'\s+'), ' ');
  }

  static DeligoFoodCategory resolve(String? rawCategory) {
    final normalized = normalize(rawCategory ?? '');
    if (normalized.isEmpty) {
      return const DeligoFoodCategory(
        id: 'other',
        label: 'Outros',
        icon: Icons.fastfood_rounded,
        color: Color(0xFF7A7A7A),
        aliases: {},
      );
    }

    for (final category in list) {
      if (category.aliases.contains(normalized) ||
          category.label.toLowerCase() == normalized) {
        return category;
      }
    }

    for (final category in list) {
      final hit = category.aliases.any(
        (alias) => normalized.contains(alias) || alias.contains(normalized),
      );
      if (hit) return category;
    }

    return const DeligoFoodCategory(
      id: 'other',
      label: 'Outros',
      icon: Icons.fastfood_rounded,
      color: Color(0xFF7A7A7A),
      aliases: {},
    );
  }
}
