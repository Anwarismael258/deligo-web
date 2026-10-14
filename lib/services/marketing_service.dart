import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

import '../config/app_env.dart';
import 'notification_dispatch_service.dart';

class MarketingService {
  MarketingService(this._supabase);

  final SupabaseClient _supabase;

  static const eventTypes = <String, String>{
    'live_music': 'Musica ao Vivo',
    'karaoke': 'Karaoke',
    'dj_party': 'DJ Party',
    'happy_hour': 'Happy Hour',
    'special_buffet': 'Buffet Especial',
    'theme_party': 'Festa Tematica',
    'sports_event': 'Evento Desportivo',
    'cultural_event': 'Evento Cultural',
    'corporate_event': 'Evento Corporativo',
    'other': 'Outro',
    'ad_campaign': 'Campanha Publicitaria',
    'promotion': 'Promocao',
    'restaurant_of_day': 'Restaurante do Dia',
  };

  static const eventCategories = <String, List<String>>{
    'Gastronomia': [
      'Happy Hour',
      'Jantar Especial',
      'Buffet Livre',
      'Rodizio',
      'Noite Tematica',
      'Festival Gastronomico',
      'Degustacao',
      'Brunch',
      'Almoco Executivo',
      'Churrascada',
    ],
    'Musica e Entretenimento': [
      'Karaoke',
      'DJ Party',
      'Musica ao Vivo',
      'Banda ao Vivo',
      'Show Acustico',
      'Concerto',
      'Festival de Musica',
      'Open Mic',
      'Jam Session',
      'Noite de Kizomba',
      'Noite de Afro House',
      'Noite de Amapiano',
      'Noite de Pandza',
      'Noite de Jazz',
      'Noite de Salsa',
      'Noite de Sertanejo',
      'Noite dos Anos 80',
      'Noite dos Anos 90',
    ],
    'Festas': [
      'Festa Tematica',
      'Festa Branca',
      'Festa Neon',
      'Festa na Piscina',
      'Sunset Party',
      'Rooftop Party',
      'After Party',
      'Festa de Aniversario',
      'Festa de Reveillon',
      'Festa de Carnaval',
      'Festa de Halloween',
      'Festa de Natal',
      'Festa de Sao Valentim',
    ],
    'Humor': ['Stand-up Comedy', 'Noite de Humor', 'Improviso'],
    'Jogos': [
      'Quiz Night',
      'Bingo',
      'Noite de Jogos',
      'Torneio de Cartas',
      'Torneio de Xadrez',
      'Torneio de Damas',
      'E-sports',
      'PlayStation Tournament',
      'FIFA Tournament',
    ],
    'Desporto': [
      'Transmissao de Futebol',
      'Final da Liga dos Campeoes',
      'Final do Mundial',
      'UFC Night',
      'Boxe',
      'Formula 1',
      'MotoGP',
      'Rugby',
      'Basquetebol',
    ],
    'Negocios': [
      'Workshop',
      'Seminario',
      'Conferencia',
      'Networking',
      'Formacao',
      'Curso',
      'Lancamento de Produto',
    ],
    'Familia': [
      'Evento Infantil',
      'Cinema ao Ar Livre',
      'Teatro Infantil',
      'Show Infantil',
      'Piquenique',
    ],
    'Cultura': [
      'Danca',
      'Teatro',
      'Exposicao',
      'Feira Cultural',
      'Feira de Artesanato',
      'Festival Cultural',
      'Sarau',
    ],
    'Bebidas': [
      'Wine Tasting',
      'Beer Festival',
      'Cocktail Night',
      'Whisky Night',
      'Gin Experience',
      'Open Bar',
    ],
    'Datas Especiais': [
      'Dia dos Namorados',
      'Dia da Mulher',
      'Dia da Crianca',
      'Dia da Independencia',
      'Black Friday Party',
      'Reveillon',
    ],
    'Outros': [
      'Lancamento',
      'Evento Beneficente',
      'Encontro de Motos',
      'Encontro de Carros',
      'Meetup',
      'Networking',
      'Outro',
    ],
  };

  static const serviceSlaHours = <String, int>{
    'promotion': 12,
    'restaurant_of_day': 24,
    'ad_campaign': 72,
  };

  int slaHoursForType(String requestType) {
    if (requestType == 'promotion' || requestType == 'restaurant_of_day') {
      return serviceSlaHours[requestType]!;
    }
    if (requestType == 'ad_campaign') return 72;
    return 48;
  }

  Future<Map<String, dynamic>?> fetchCurrentStaffProfile() async {
    final userId = _supabase.auth.currentUser?.id;
    if (userId == null || userId.isEmpty) return null;

    final profile = await _supabase
        .from('profiles')
        .select('id, full_name, phone, role, city, staff_active')
        .eq('id', userId)
        .maybeSingle();
    if (profile == null) return null;
    return Map<String, dynamic>.from(profile);
  }

  Future<Map<String, dynamic>?> fetchRestaurantForCurrentUser() async {
    final userId = _supabase.auth.currentUser?.id;
    if (userId == null || userId.isEmpty) return null;

    final restaurant = await _supabase
        .from('restaurants')
        .select('id, owner_id, name, address, city, neighborhood, phone')
        .eq('owner_id', userId)
        .maybeSingle();
    if (restaurant == null) return null;
    return Map<String, dynamic>.from(restaurant);
  }

  Future<List<Map<String, dynamic>>> fetchMarketingRequests({
    String status = 'all',
    String query = '',
    String? restaurantId,
  }) async {
    var request = _supabase
        .from('marketing_requests')
        .select(
          'id, restaurant_id, requested_by, assigned_to, request_type, '
          'event_name, description, event_date, event_time, location, '
          'sells_tickets, ticket_price, ticket_quantity, notes, status, '
          'event_category, event_type_detail, event_end_time, max_capacity, '
          'ticket_options, rules, refund_policy, '
          'objective, target_audience, age_rating, logo_url, photo_urls, '
          'brand_colors, social_links, website, sales_start_at, sales_end_at, '
          'sla_due_at, revision_notes, '
          'restaurant_approved_at, published_at, poster_url, banner_url, '
          'campaign_title, campaign_description, '
          'created_at, updated_at, restaurants(name, phone, city, neighborhood)',
        );

    if (status != 'all') {
      request = request.eq('status', status);
    }
    if (restaurantId != null && restaurantId.isNotEmpty) {
      request = request.eq('restaurant_id', restaurantId);
    }

    final result = await request
        .order('created_at', ascending: false)
        .limit(150);
    final rows = (result as List)
        .cast<Map<String, dynamic>>()
        .map(Map<String, dynamic>.from)
        .toList();

    final trimmed = query.trim().toLowerCase();
    if (trimmed.isEmpty) return rows;
    return rows.where((row) {
      final restaurant = row['restaurants'] is Map
          ? Map<String, dynamic>.from(row['restaurants'] as Map)
          : const <String, dynamic>{};
      final haystack = [
        row['event_name'],
        row['description'],
        row['request_type'],
        row['location'],
        restaurant['name'],
        restaurant['city'],
      ].map((value) => value?.toString().toLowerCase() ?? '').join(' ');
      return haystack.contains(trimmed);
    }).toList();
  }

  Future<List<Map<String, dynamic>>> searchRestaurantsForMarketing([
    String query = '',
  ]) async {
    final trimmed = query.trim();
    var request = _supabase
        .from('restaurants')
        .select('id, owner_id, name, phone, city, neighborhood, address');
    if (trimmed.isNotEmpty) {
      request = request.ilike('name', '%$trimmed%');
    }
    final result = await request.order('name', ascending: true).limit(40);
    return (result as List)
        .cast<Map<String, dynamic>>()
        .map(Map<String, dynamic>.from)
        .toList();
  }

  Future<List<Map<String, dynamic>>> fetchPublishedEvents({
    String? restaurantId,
  }) async {
    var request = _supabase
        .from('marketing_events')
        .select(
          'id, request_id, restaurant_id, title, description, event_type, '
          'event_date, event_time, location, poster_url, banner_url, '
          'sells_tickets, ticket_price, ticket_quantity, tickets_sold, '
          'tickets_used, '
          'event_category, event_type_detail, event_end_time, max_capacity, '
          'ticket_options, rules, refund_policy, '
          'sales_start_at, sales_end_at, '
          'gross_revenue, deligo_commission, net_amount, qr_code_seed, '
          'refunded_tickets, refunded_amount, refunded_restaurant_amount, '
          'refunded_commission, cancellation_reason, cancelled_at, '
          'status, published_at, created_at, updated_at, restaurants(name)',
        );
    if (restaurantId != null && restaurantId.isNotEmpty) {
      request = request.eq('restaurant_id', restaurantId);
    }
    final result = await request
        .inFilter('status', ['published', 'sold_out'])
        .order('event_date', ascending: true)
        .limit(150);
    return (result as List)
        .cast<Map<String, dynamic>>()
        .map(Map<String, dynamic>.from)
        .where((event) => !_eventHasEnded(event))
        .toList();
  }

  Future<List<Map<String, dynamic>>> fetchEventTickets({
    required String eventId,
    String? status,
  }) async {
    var request = _supabase
        .from('marketing_event_tickets')
        .select(
          'id,event_id,buyer_id,ticket_code,qr_code,price,restaurant_amount,'
          'deligo_commission,ticket_type_id,ticket_type_name,status,sold_at,used_at,validated_by,'
          'profiles:buyer_id(full_name,phone,email),'
          'validator:validated_by(full_name,phone,email)',
        )
        .eq('event_id', eventId);
    if (status?.trim().isNotEmpty == true) {
      request = request.eq('status', status!.trim());
    }
    final result = await request
        .order('created_at', ascending: false)
        .limit(500);
    return (result as List)
        .cast<Map<String, dynamic>>()
        .map(Map<String, dynamic>.from)
        .toList();
  }

  Future<void> createRestaurantRequest({
    required String restaurantId,
    required String requestType,
    required String eventName,
    required String description,
    required String eventDate,
    required String eventTime,
    required String location,
    required bool sellsTickets,
    double? ticketPrice,
    int? ticketQuantity,
    String? eventCategory,
    String? eventTypeDetail,
    String? eventEndTime,
    int? maxCapacity,
    List<Map<String, dynamic>> ticketOptions = const [],
    String? rules,
    String? refundPolicy,
    String objective = 'increase_sales',
    String targetAudience = 'all',
    String ageRating = 'free',
    String? logoUrl,
    List<String> photoUrls = const [],
    String? bannerUrl,
    String? brandColors,
    String? socialLinks,
    String? website,
    String? salesStartAt,
    String? salesEndAt,
    String? notes,
  }) async {
    final userId = _supabase.auth.currentUser?.id;
    if (userId == null || userId.isEmpty) {
      throw Exception('Sessao expirada. Entre novamente.');
    }

    final trimmedSalesStartAt = salesStartAt?.trim();
    final trimmedSalesEndAt = salesEndAt?.trim();

    final restaurantName = await _restaurantNameById(restaurantId);
    final requestIdValue = await _supabase.rpc(
      'submit_marketing_event_request',
      params: {
        'p_payload': {
          'restaurant_id': restaurantId,
          'request_type': requestType,
          'event_name': eventName.trim(),
          'description': description.trim(),
          'event_date': eventDate,
          'event_time': eventTime,
          'location': location.trim(),
          'sells_tickets': sellsTickets,
          'ticket_price': sellsTickets ? ticketPrice : null,
          'ticket_quantity': sellsTickets ? ticketQuantity : null,
          'event_category': eventCategory?.trim(),
          'event_type_detail': eventTypeDetail?.trim(),
          'event_end_time': eventEndTime?.trim().isNotEmpty == true
              ? eventEndTime!.trim()
              : null,
          'max_capacity': maxCapacity,
          'ticket_options': ticketOptions,
          'rules': rules?.trim(),
          'refund_policy': refundPolicy?.trim(),
          'objective': objective,
          'target_audience': targetAudience,
          'age_rating': ageRating,
          'logo_url': logoUrl?.trim(),
          'photo_urls': photoUrls,
          'banner_url': bannerUrl?.trim(),
          'poster_url': bannerUrl?.trim(),
          'brand_colors': brandColors?.trim(),
          'social_links': socialLinks?.trim(),
          'website': website?.trim(),
          'sales_start_at':
              sellsTickets && trimmedSalesStartAt?.isNotEmpty == true
              ? trimmedSalesStartAt
              : null,
          'sales_end_at': sellsTickets && trimmedSalesEndAt?.isNotEmpty == true
              ? trimmedSalesEndAt
              : null,
          'sla_hours': slaHoursForType(requestType),
          'notes': notes?.trim(),
        },
      },
    );

    final requestId = requestIdValue?.toString() ?? '';
    await _notifyMarketingTeamOfNewRequest(
      requestId: requestId,
      restaurantId: restaurantId,
      restaurantName: restaurantName,
      eventName: eventName,
      requestType: requestType,
    );
  }

  Future<String> _restaurantNameById(String restaurantId) async {
    final row = await _supabase
        .from('restaurants')
        .select('name')
        .eq('id', restaurantId)
        .maybeSingle();
    return row?['name']?.toString().trim().isNotEmpty == true
        ? row!['name'].toString()
        : 'Restaurante';
  }

  Future<void> _notifyMarketingTeamOfNewRequest({
    required String requestId,
    required String restaurantId,
    required String restaurantName,
    required String eventName,
    required String requestType,
  }) async {
    if (requestId.isEmpty) return;
    try {
      await NotificationDispatchService.instance.sendToRole(
        targetRole: 'marketing_agent',
        type: 'MARKETING_REQUEST_CREATED',
        title: 'Novo pedido de marketing',
        body:
            '$restaurantName solicitou ${typeLabel(requestType)}: ${eventName.trim()}',
        action: '/marketing-dashboard',
        entityId: requestId,
        priority: 'HIGH',
        channel: 'marketing',
        data: {
          'request_id': requestId,
          'restaurant_id': restaurantId,
          'restaurant_name': restaurantName,
          'request_type': requestType,
        },
        metadata: {'dispatch_key': 'marketing_request_created:$requestId'},
      );
    } catch (error) {
      debugPrint('Erro ao notificar equipa de marketing: $error');
    }
  }

  Future<void> saveMarketingDraft({
    required String requestId,
    required String campaignTitle,
    required String campaignDescription,
    String? posterUrl,
    String? bannerUrl,
  }) async {
    final userId = _supabase.auth.currentUser?.id;
    if (userId == null || userId.isEmpty) {
      throw Exception('Sessao expirada. Entre novamente.');
    }

    await _supabase
        .from('marketing_requests')
        .update({
          'assigned_to': userId,
          'campaign_title': campaignTitle.trim(),
          'campaign_description': campaignDescription.trim(),
          'poster_url': posterUrl?.trim(),
          'banner_url': bannerUrl?.trim(),
          'status': 'ready_for_restaurant_review',
          'updated_at': DateTime.now().toUtc().toIso8601String(),
        })
        .eq('id', requestId);
  }

  Future<void> requestRevision({
    required String requestId,
    required String notes,
  }) async {
    await _supabase
        .from('marketing_requests')
        .update({
          'status': 'revision_requested',
          'revision_notes': notes.trim(),
          'updated_at': DateTime.now().toUtc().toIso8601String(),
        })
        .eq('id', requestId);
  }

  Future<void> rejectRequest({
    required String requestId,
    required String reason,
  }) async {
    await _supabase
        .from('marketing_requests')
        .update({
          'status': 'rejected',
          'revision_notes': reason.trim(),
          'updated_at': DateTime.now().toUtc().toIso8601String(),
        })
        .eq('id', requestId);
  }

  Future<void> resubmitRestaurantRequest({
    required String requestId,
    required String bannerUrl,
  }) async {
    await _supabase
        .from('marketing_requests')
        .update({
          'banner_url': bannerUrl.trim(),
          'poster_url': bannerUrl.trim(),
          'status': 'received',
          'revision_notes': null,
          'assigned_to': null,
          'updated_at': DateTime.now().toUtc().toIso8601String(),
        })
        .eq('id', requestId);
  }

  Future<List<Map<String, dynamic>>> fetchRequestMessages(
    String requestId,
  ) async {
    final result = await _supabase
        .from('marketing_request_messages')
        .select(
          'id, request_id, sender_id, sender_role, body, attachment_url, created_at',
        )
        .eq('request_id', requestId)
        .order('created_at', ascending: true)
        .limit(200);
    return (result as List)
        .cast<Map<String, dynamic>>()
        .map(Map<String, dynamic>.from)
        .toList();
  }

  Future<void> sendRequestMessage({
    required String requestId,
    required String senderRole,
    required String body,
    String? attachmentUrl,
  }) async {
    final userId = _supabase.auth.currentUser?.id;
    if (userId == null || userId.isEmpty) {
      throw Exception('Sessao expirada. Entre novamente.');
    }
    await _supabase.from('marketing_request_messages').insert({
      'request_id': requestId,
      'sender_id': userId,
      'sender_role': senderRole,
      'body': body.trim(),
      'attachment_url': attachmentUrl?.trim(),
    });
  }

  Future<void> approveAndPublishRequest(String requestId) async {
    await _supabase.rpc(
      'approve_marketing_request_and_publish',
      params: {'p_request_id': requestId},
    );
  }

  Future<Map<String, dynamic>> cancelEventAndRefund({
    required String eventId,
    required String reason,
  }) async {
    final response = await _supabase.rpc(
      'cancel_marketing_event_and_refund',
      params: {'p_event_id': eventId, 'p_reason': reason.trim()},
    );
    if (response is Map<String, dynamic>) return response;
    if (response is Map) {
      return response.map((key, value) => MapEntry(key.toString(), value));
    }
    return const <String, dynamic>{};
  }

  Future<Map<String, dynamic>> validateTicket(String ticketCode) async {
    final response = await _supabase.rpc(
      'validate_marketing_event_ticket',
      params: {'p_ticket_code': ticketCode.trim()},
    );
    if (response is Map<String, dynamic>) return response;
    if (response is Map) {
      return response.map((key, value) => MapEntry(key.toString(), value));
    }
    return <String, dynamic>{'success': false, 'error': response?.toString()};
  }

  Future<Map<String, dynamic>?> fetchCampaignById(String campaignId) async {
    if (campaignId.trim().isEmpty || campaignId.startsWith('event-')) {
      return null;
    }
    final result = await _supabase
        .from('marketing_campaigns')
        .select(
          'id, restaurant_id, event_id, title, subtitle, description, '
          'placement, campaign_type, coupon_code, discount_type, discount_value, '
          'starts_at, ends_at, image_url, media_url, video_url, action_label, '
          'priority, type, objective, target_type, target_id, budget, status, '
          'views, clicks, conversions, revenue_generated, metadata, '
          'restaurants(id, name, phone, address, city, neighborhood, image_url, rating)',
        )
        .eq('id', campaignId)
        .maybeSingle();
    if (result == null) return null;
    return Map<String, dynamic>.from(result);
  }

  Future<Map<String, dynamic>?> fetchEventById(String eventId) async {
    final normalized = eventId.replaceFirst('event-', '').trim();
    if (normalized.isEmpty) return null;
    final result = await _supabase
        .from('marketing_events')
        .select(
          'id, request_id, restaurant_id, title, description, event_type, '
          'event_date, event_time, location, poster_url, banner_url, '
          'sells_tickets, ticket_price, ticket_quantity, tickets_sold, '
          'tickets_used, event_category, event_type_detail, event_end_time, '
          'sales_start_at, sales_end_at, '
          'gross_revenue, deligo_commission, net_amount, qr_code_seed, '
          'status, published_at, created_at, updated_at, restaurants(id, name, phone, address, city, neighborhood, image_url, rating)',
        )
        .eq('id', normalized)
        .maybeSingle();
    if (result == null) return null;
    return Map<String, dynamic>.from(result);
  }

  Future<List<Map<String, dynamic>>> fetchEventTicketTypes(
    String eventId,
  ) async {
    final normalized = eventId.replaceFirst('event-', '').trim();
    if (normalized.isEmpty) return const [];
    final result = await _supabase
        .from('event_ticket_types')
        .select('id,event_id,ticket_name,price,quantity,sold,remaining,status')
        .eq('event_id', normalized)
        .inFilter('status', ['active', 'sold_out'])
        .order('price', ascending: true)
        .order('created_at', ascending: true);
    return (result as List)
        .cast<Map<String, dynamic>>()
        .map(Map<String, dynamic>.from)
        .toList();
  }

  Future<List<Map<String, dynamic>>> buyEventTickets({
    required String eventId,
    required int quantity,
    String? ticketTypeId,
  }) async {
    final normalizedEventId = eventId.replaceFirst('event-', '').trim();
    final response = await _supabase.rpc(
      'buy_marketing_event_tickets',
      params: {
        'p_event_id': normalizedEventId,
        'p_quantity': quantity,
        'p_ticket_type_id': ticketTypeId?.trim().isNotEmpty == true
            ? ticketTypeId!.trim()
            : null,
      },
    );
    final payload = response is Map
        ? Map<String, dynamic>.from(response)
        : const <String, dynamic>{};
    final ticketIds = (payload['ticket_ids'] as List? ?? const [])
        .map((id) => id.toString())
        .where((id) => id.isNotEmpty)
        .toList();
    if (ticketIds.isEmpty) return const [];

    final result = await _supabase
        .from('marketing_event_tickets')
        .select(
          'id, event_id, buyer_id, ticket_code, qr_code, ticket_type_id, ticket_type_name, price, status, sold_at, used_at, marketing_events(title, event_date, event_time, restaurant_id, restaurants(id, name, owner_id))',
        )
        .inFilter('id', ticketIds)
        .order('sold_at', ascending: true);
    return (result as List)
        .cast<Map<String, dynamic>>()
        .map(Map<String, dynamic>.from)
        .toList();
  }

  Future<List<Map<String, dynamic>>> fetchClientCampaignCenter({
    String? city,
    String? neighborhood,
    String? userId,
    int limit = 20,
    List<Map<String, dynamic>>? homeSections,
  }) async {
    final sections =
        homeSections ??
        await fetchHomeCampaignSections(
          city: city,
          neighborhood: neighborhood,
          userId: userId,
          limit: limit,
        );
    final flat = <Map<String, dynamic>>[];
    for (final section in sections) {
      final items = (section['items'] as List?) ?? const [];
      for (final item in items.whereType<Map>()) {
        flat.add(item.map((key, value) => MapEntry(key.toString(), value)));
      }
    }
    final rows = <Map<String, dynamic>>[...flat];

    var request = _supabase
        .from('marketing_campaigns')
        .select(
          'id, restaurant_id, event_id, title, subtitle, description, '
          'placement, campaign_type, coupon_code, discount_type, discount_value, '
          'starts_at, ends_at, image_url, media_url, video_url, action_label, '
          'priority, type, objective, target_type, target_id, budget, status, '
          'views, clicks, conversions, revenue_generated, metadata, '
          'restaurants(id, name, rating, image_url, city, neighborhood)',
        );

    final now = DateTime.now().toUtc().toIso8601String();
    final result = await request
        .eq('active', true)
        .lte('starts_at', now)
        .or('ends_at.is.null,ends_at.gte.$now')
        .order('priority', ascending: false)
        .order('created_at', ascending: false)
        .limit(limit);

    final campaignRows = (result as List)
        .cast<Map<String, dynamic>>()
        .map(Map<String, dynamic>.from)
        .toList();
    rows.addAll(
      campaignRows.where((campaign) {
        final id = campaign['id']?.toString();
        if (id == null || id.isEmpty) return true;
        return !rows.any((row) => row['id']?.toString() == id);
      }),
    );

    final events = await fetchPublishedEvents();
    final eventCampaigns = events.map(_eventToClientCampaign).toList();
    rows.addAll(
      eventCampaigns.where((eventCampaign) {
        final eventId = eventCampaign['event_id']?.toString();
        if (eventId == null || eventId.isEmpty) return true;
        return !rows.any((row) => row['event_id']?.toString() == eventId);
      }),
    );

    final normalizedCity = city?.trim().toLowerCase() ?? '';
    final normalizedNeighborhood = neighborhood?.trim().toLowerCase() ?? '';
    return rows.where((row) {
      final metadata =
          (row['metadata'] as Map?)?.cast<String, dynamic>() ?? const {};
      final cities = _stringList(metadata['cities']);
      final neighborhoods = _stringList(metadata['neighborhoods']);
      final cityOk =
          cities.isEmpty ||
          cities.contains(normalizedCity) ||
          normalizedCity.isEmpty;
      final neighborhoodOk =
          neighborhoods.isEmpty ||
          neighborhoods.contains(normalizedNeighborhood) ||
          normalizedNeighborhood.isEmpty;
      return cityOk && neighborhoodOk;
    }).toList();
  }

  Map<String, dynamic> _eventToClientCampaign(Map<String, dynamic> event) {
    final restaurant = event['restaurants'] is Map
        ? Map<String, dynamic>.from(event['restaurants'] as Map)
        : const <String, dynamic>{};
    final sellsTickets = event['sells_tickets'] == true;
    final imageUrl = event['banner_url']?.toString().trim().isNotEmpty == true
        ? event['banner_url']?.toString()
        : event['poster_url']?.toString();
    return {
      'id': 'event-${event['id']}',
      'event_id': event['id'],
      'restaurant_id': event['restaurant_id'],
      'title': event['title']?.toString() ?? 'Evento DeliGo',
      'subtitle': sellsTickets
          ? 'Bilhetes disponiveis no DeliGo'
          : event['location']?.toString(),
      'description': event['description']?.toString(),
      'placement': sellsTickets ? 'tickets' : 'events_today',
      'campaign_type': sellsTickets ? 'ticket' : 'event',
      'starts_at': event['published_at']?.toString(),
      'ends_at': _eventEndDateTime(event)?.toIso8601String(),
      'image_url': imageUrl,
      'action_label': sellsTickets ? 'Ver bilhetes' : 'Ver evento',
      'priority': 80,
      'metadata': {
        'event_date': event['event_date']?.toString(),
        'event_time': event['event_time']?.toString(),
        'event_end_time': event['event_end_time']?.toString(),
        'location': event['location']?.toString(),
        'sales_start_at': event['sales_start_at']?.toString(),
        'sales_end_at': event['sales_end_at']?.toString(),
      },
      'restaurants': restaurant,
    };
  }

  Future<List<Map<String, dynamic>>> fetchHomeCampaignSections({
    String? city,
    String? neighborhood,
    String? userId,
    int limit = 20,
  }) async {
    final supabaseUrl = AppEnv.supabaseUrl.trim();
    final anonKey = AppEnv.supabaseAnonKey.trim();
    if (supabaseUrl.isEmpty || anonKey.isEmpty) return const [];

    final uri = Uri.parse('$supabaseUrl/functions/v1/campaigns-home').replace(
      queryParameters: {
        if (userId?.trim().isNotEmpty == true) 'user': userId!.trim(),
        if (city?.trim().isNotEmpty == true) 'city': city!.trim(),
        if (neighborhood?.trim().isNotEmpty == true)
          'neighborhood': neighborhood!.trim(),
        'limit': limit.toString(),
      },
    );
    final token = _supabase.auth.currentSession?.accessToken;
    final response = await http
        .get(
          uri,
          headers: {
            'apikey': anonKey,
            if (token?.isNotEmpty == true) 'Authorization': 'Bearer $token',
          },
        )
        .timeout(const Duration(seconds: 12));

    if (response.statusCode < 200 || response.statusCode >= 300) {
      return const [];
    }
    final payload = jsonDecode(response.body);
    if (payload is! Map) return const [];
    final sections = payload['sections'];
    if (sections is! List) return const [];
    return sections
        .whereType<Map>()
        .map(
          (item) => item.map((key, value) => MapEntry(key.toString(), value)),
        )
        .toList();
  }

  bool _eventHasEnded(Map<String, dynamic> event) {
    final end = _eventEndDateTime(event);
    if (end == null) return false;
    return end.isBefore(DateTime.now());
  }

  DateTime? _eventEndDateTime(Map<String, dynamic> event) {
    final date = event['event_date']?.toString().trim();
    if (date == null || date.isEmpty) return null;
    final endTime = event['event_end_time']?.toString().trim();
    final startTime = event['event_time']?.toString().trim();
    final time = (endTime != null && endTime.isNotEmpty)
        ? endTime
        : (startTime != null && startTime.isNotEmpty ? startTime : '23:59');
    return DateTime.tryParse('${date}T$time');
  }

  Future<Map<String, dynamic>> applyCouponCode(String code) async {
    final response = await _supabase.rpc(
      'apply_marketing_coupon',
      params: {'p_code': code.trim().toUpperCase()},
    );
    if (response is Map<String, dynamic>) return response;
    if (response is Map) {
      return response.map((key, value) => MapEntry(key.toString(), value));
    }
    return <String, dynamic>{'success': false, 'error': response?.toString()};
  }

  Future<Map<String, dynamic>> fetchMarketingSettings() async {
    final result = await _supabase
        .from('marketing_settings')
        .select(
          'home_banner_limit, sponsored_limit, featured_limit, video_limit, '
          'featured_restaurants_limit, featured_products_limit, updated_at',
        )
        .eq('id', true)
        .maybeSingle();
    if (result == null) {
      return const {
        'home_banner_limit': 5,
        'sponsored_limit': 10,
        'featured_limit': 20,
        'video_limit': 1,
        'featured_restaurants_limit': 10,
        'featured_products_limit': 10,
      };
    }
    return Map<String, dynamic>.from(result);
  }

  Future<void> createCampaign({
    String? restaurantId,
    String? eventId,
    required String title,
    String? subtitle,
    String? description,
    required String placement,
    required String campaignType,
    String? type,
    String? objective,
    String? targetType,
    String? targetId,
    String? couponCode,
    String? discountType,
    double? discountValue,
    String? startsAt,
    String? endsAt,
    String? imageUrl,
    String? videoUrl,
    String actionLabel = 'Ver agora',
    int priority = 0,
    double budget = 0,
    String status = 'published',
    Map<String, dynamic> metadata = const {},
  }) async {
    final userId = _supabase.auth.currentUser?.id;
    if (userId == null || userId.isEmpty) {
      throw Exception('Sessao expirada. Entre novamente.');
    }

    await _supabase.from('marketing_campaigns').insert({
      'restaurant_id': restaurantId?.trim().isNotEmpty == true
          ? restaurantId!.trim()
          : null,
      'event_id': eventId?.trim().isNotEmpty == true ? eventId!.trim() : null,
      'created_by': userId,
      'title': title.trim(),
      'subtitle': subtitle?.trim(),
      'description': description?.trim(),
      'placement': placement,
      'campaign_type': campaignType,
      'type': type?.trim().isNotEmpty == true ? type!.trim() : campaignType,
      'objective': objective?.trim().isNotEmpty == true
          ? objective!.trim()
          : campaignType,
      'target_type': targetType?.trim().isNotEmpty == true
          ? targetType!.trim()
          : eventId?.trim().isNotEmpty == true
          ? 'event'
          : restaurantId?.trim().isNotEmpty == true
          ? 'restaurant'
          : 'none',
      'target_id': targetId?.trim().isNotEmpty == true
          ? targetId!.trim()
          : eventId?.trim().isNotEmpty == true
          ? eventId!.trim()
          : restaurantId?.trim().isNotEmpty == true
          ? restaurantId!.trim()
          : null,
      'coupon_code': couponCode?.trim().isNotEmpty == true
          ? couponCode!.trim().toUpperCase()
          : null,
      'discount_type': discountType,
      'discount_value': discountValue,
      'starts_at': startsAt?.trim().isNotEmpty == true
          ? startsAt!.trim()
          : DateTime.now().toUtc().toIso8601String(),
      'ends_at': endsAt?.trim().isNotEmpty == true ? endsAt!.trim() : null,
      'image_url': imageUrl?.trim(),
      'media_url': imageUrl?.trim(),
      'video_url': videoUrl?.trim(),
      'action_label': actionLabel.trim().isEmpty
          ? 'Ver agora'
          : actionLabel.trim(),
      'priority': priority,
      'budget': budget,
      'status': status,
      'metadata': metadata,
      'active': status == 'published' || status == 'scheduled',
    });
  }

  List<String> _stringList(dynamic value) {
    if (value is List) {
      return value
          .map((item) => item.toString().trim().toLowerCase())
          .where((item) => item.isNotEmpty)
          .toList();
    }
    return const [];
  }

  String typeLabel(String value) => eventTypes[value] ?? value;
}
