import 'package:equatable/equatable.dart';

// ──────────────────────────────────────────────
// Enums (match API uppercase values exactly)
// ──────────────────────────────────────────────

enum TaskPriority {
  low('LOW'),
  medium('MEDIUM'),
  high('HIGH'),
  critical('CRITICAL');

  const TaskPriority(this.value);
  final String value;

  static TaskPriority fromValue(String v) =>
      TaskPriority.values.firstWhere((e) => e.value == v.toUpperCase());

  /// Display label for UI chips.
  String get label => switch (this) {
        TaskPriority.low => 'Low',
        TaskPriority.medium => 'Medium',
        TaskPriority.high => 'High',
        TaskPriority.critical => 'Critical',
      };
}

enum TaskType {
  oneTime('ONE_TIME'),
  recurring('RECURRING');

  const TaskType(this.value);
  final String value;

  static TaskType fromValue(String v) =>
      TaskType.values.firstWhere((e) => e.value == v.toUpperCase());

  String get label => switch (this) {
        TaskType.oneTime => 'One-time',
        TaskType.recurring => 'Recurring',
      };
}

/// Stored statuses returned by the API — `overdue` is a query param only.
enum TaskStatus {
  pending('PENDING'),
  completed('COMPLETED'),
  cancelled('CANCELLED');

  const TaskStatus(this.value);
  final String value;

  static TaskStatus fromValue(String v) =>
      TaskStatus.values.firstWhere((e) => e.value == v.toUpperCase());

  String get label => switch (this) {
        TaskStatus.pending => 'Pending',
        TaskStatus.completed => 'Completed',
        TaskStatus.cancelled => 'Cancelled',
      };
}

// ──────────────────────────────────────────────
// Task entity
// ──────────────────────────────────────────────

class Task extends Equatable {
  const Task({
    required this.id,
    required this.title,
    required this.priority,
    required this.taskType,
    required this.status,
    required this.isOverdue,
    required this.sortOrder,
    required this.isDetached,
    required this.attachmentCount,
    required this.createdAt,
    required this.updatedAt,
    this.description,
    this.address,
    this.startAt,
    this.endAt,
    this.completedAt,
    this.cancelledAt,
    this.recurringRuleId,
  });

  final String id;
  final String title;
  final String? description;
  final String? address;
  final TaskPriority priority;
  final TaskType taskType;
  final TaskStatus status;
  final bool isOverdue;
  final int sortOrder;
  final DateTime? startAt;
  final DateTime? endAt;
  final DateTime? completedAt;
  final DateTime? cancelledAt;
  final String? recurringRuleId;
  final bool isDetached;
  final int attachmentCount;
  final DateTime createdAt;
  final DateTime updatedAt;

  factory Task.fromJson(Map<String, dynamic> json) => Task(
        id: json['id'] as String,
        title: json['title'] as String,
        description: json['description'] as String?,
        address: json['address'] as String?,
        priority: TaskPriority.fromValue(json['priority'] as String),
        taskType: TaskType.fromValue(json['task_type'] as String),
        status: TaskStatus.fromValue(json['status'] as String),
        isOverdue: json['is_overdue'] as bool? ?? false,
        sortOrder: json['sort_order'] as int? ?? 0,
        startAt: _parseDate(json['start_at']),
        endAt: _parseDate(json['end_at']),
        completedAt: _parseDate(json['completed_at']),
        cancelledAt: _parseDate(json['cancelled_at']),
        recurringRuleId: json['recurring_rule_id'] as String?,
        isDetached: json['is_detached'] as bool? ?? false,
        attachmentCount: json['attachment_count'] as int? ?? 0,
        createdAt: DateTime.parse(json['created_at'] as String),
        updatedAt: DateTime.parse(json['updated_at'] as String),
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        if (description != null) 'description': description,
        if (address != null) 'address': address,
        'priority': priority.value,
        'task_type': taskType.value,
        'status': status.value,
        'is_overdue': isOverdue,
        'sort_order': sortOrder,
        if (startAt != null) 'start_at': startAt!.toUtc().toIso8601String(),
        if (endAt != null) 'end_at': endAt!.toUtc().toIso8601String(),
        if (completedAt != null)
          'completed_at': completedAt!.toUtc().toIso8601String(),
        if (cancelledAt != null)
          'cancelled_at': cancelledAt!.toUtc().toIso8601String(),
        if (recurringRuleId != null) 'recurring_rule_id': recurringRuleId,
        'is_detached': isDetached,
        'attachment_count': attachmentCount,
        'created_at': createdAt.toUtc().toIso8601String(),
        'updated_at': updatedAt.toUtc().toIso8601String(),
      };

  Task copyWith({
    String? id,
    String? title,
    String? description,
    String? address,
    TaskPriority? priority,
    TaskType? taskType,
    TaskStatus? status,
    bool? isOverdue,
    int? sortOrder,
    DateTime? startAt,
    DateTime? endAt,
    DateTime? completedAt,
    DateTime? cancelledAt,
    String? recurringRuleId,
    bool? isDetached,
    int? attachmentCount,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) =>
      Task(
        id: id ?? this.id,
        title: title ?? this.title,
        description: description ?? this.description,
        address: address ?? this.address,
        priority: priority ?? this.priority,
        taskType: taskType ?? this.taskType,
        status: status ?? this.status,
        isOverdue: isOverdue ?? this.isOverdue,
        sortOrder: sortOrder ?? this.sortOrder,
        startAt: startAt ?? this.startAt,
        endAt: endAt ?? this.endAt,
        completedAt: completedAt ?? this.completedAt,
        cancelledAt: cancelledAt ?? this.cancelledAt,
        recurringRuleId: recurringRuleId ?? this.recurringRuleId,
        isDetached: isDetached ?? this.isDetached,
        attachmentCount: attachmentCount ?? this.attachmentCount,
        createdAt: createdAt ?? this.createdAt,
        updatedAt: updatedAt ?? this.updatedAt,
      );

  @override
  List<Object?> get props => [
        id, title, description, address, priority, taskType, status,
        isOverdue, sortOrder, startAt, endAt, completedAt, cancelledAt,
        recurringRuleId, isDetached, attachmentCount, createdAt, updatedAt,
      ];

  static DateTime? _parseDate(dynamic v) =>
      v is String ? DateTime.parse(v) : null;
}

// ──────────────────────────────────────────────
// Filter / Sort
// ──────────────────────────────────────────────

/// Filter for GET /tasks — includes calculated `overdue` pseudo-status.
enum FilterStatus {
  all(''),
  pending('pending'),
  completed('completed'),
  cancelled('cancelled'),
  overdue('overdue');

  const FilterStatus(this.value);
  final String value;

  String get label => switch (this) {
        FilterStatus.all => 'All',
        FilterStatus.pending => 'Pending',
        FilterStatus.completed => 'Completed',
        FilterStatus.cancelled => 'Cancelled',
        FilterStatus.overdue => 'Overdue',
      };
}

enum FilterPriority {
  all(''),
  low('low'),
  medium('medium'),
  high('high'),
  critical('critical');

  const FilterPriority(this.value);
  final String value;

  String get label => switch (this) {
        FilterPriority.all => 'All',
        FilterPriority.low => 'Low',
        FilterPriority.medium => 'Medium',
        FilterPriority.high => 'High',
        FilterPriority.critical => 'Critical',
      };
}

enum FilterType {
  all(''),
  oneTime('one_time'),
  recurring('recurring');

  const FilterType(this.value);
  final String value;

  String get label => switch (this) {
        FilterType.all => 'All',
        FilterType.oneTime => 'One-time',
        FilterType.recurring => 'Recurring',
      };
}

enum SortField {
  sortOrder('sort_order'),
  dueDate('due_date'),
  priority('priority'),
  createdAt('created_at');

  const SortField(this.value);
  final String value;

  String get label => switch (this) {
        SortField.sortOrder => 'Custom',
        SortField.dueDate => 'Due Date',
        SortField.priority => 'Priority',
        SortField.createdAt => 'Created',
      };
}

class TaskFilter extends Equatable {
  const TaskFilter({
    this.status = FilterStatus.all,
    this.priority = FilterPriority.all,
    this.type = FilterType.all,
    this.sort = SortField.sortOrder,
    this.order = 'asc',
    this.page = 1,
    this.perPage = 50,
    this.search,
    this.from,
    this.to,
  });

  final FilterStatus status;
  final FilterPriority priority;
  final FilterType type;
  final SortField sort;
  final String order;
  final int page;
  final int perPage;
  final String? search;
  final DateTime? from;
  final DateTime? to;

  bool get hasActiveFilter =>
      status != FilterStatus.all ||
      priority != FilterPriority.all ||
      type != FilterType.all ||
      sort != SortField.sortOrder ||
      search != null;

  Map<String, String> toQueryParams() => {
        if (status != FilterStatus.all) 'status': status.value,
        if (priority != FilterPriority.all) 'priority': priority.value,
        if (type != FilterType.all) 'type': type.value,
        'sort': sort.value,
        'order': order,
        'page': '$page',
        'per_page': '$perPage',
        if (search != null && search!.isNotEmpty) 'search': search!,
        if (from != null) 'from': from!.toUtc().toIso8601String(),
        if (to != null) 'to': to!.toUtc().toIso8601String(),
      };

  TaskFilter copyWith({
    FilterStatus? status,
    FilterPriority? priority,
    FilterType? type,
    SortField? sort,
    String? order,
    int? page,
    int? perPage,
    String? search,
    DateTime? from,
    DateTime? to,
  }) =>
      TaskFilter(
        status: status ?? this.status,
        priority: priority ?? this.priority,
        type: type ?? this.type,
        sort: sort ?? this.sort,
        order: order ?? this.order,
        page: page ?? this.page,
        perPage: perPage ?? this.perPage,
        search: search ?? this.search,
        from: from ?? this.from,
        to: to ?? this.to,
      );

  static const empty = TaskFilter();

  @override
  List<Object?> get props =>
      [status, priority, type, sort, order, page, perPage, search, from, to];
}

// ──────────────────────────────────────────────
// Pagination
// ──────────────────────────────────────────────

class PaginationMeta extends Equatable {
  const PaginationMeta({
    required this.total,
    required this.page,
    required this.perPage,
    required this.totalPages,
  });

  final int total;
  final int page;
  final int perPage;
  final int totalPages;

  factory PaginationMeta.fromJson(Map<String, dynamic> json) => PaginationMeta(
        total: json['total'] as int,
        page: json['page'] as int,
        perPage: json['per_page'] as int,
        totalPages: json['total_pages'] as int,
      );

  @override
  List<Object?> get props => [total, page, perPage, totalPages];
}

class TaskListResponse extends Equatable {
  const TaskListResponse({required this.data, required this.meta});

  final List<Task> data;
  final PaginationMeta meta;

  factory TaskListResponse.fromJson(Map<String, dynamic> json) =>
      TaskListResponse(
        data: (json['data'] as List<dynamic>)
            .map((e) => Task.fromJson(e as Map<String, dynamic>))
            .toList(),
        meta: PaginationMeta.fromJson(json['meta'] as Map<String, dynamic>),
      );

  @override
  List<Object?> get props => [data, meta];
}

// ──────────────────────────────────────────────
// Gamification delta
// ──────────────────────────────────────────────

class BadgeAward extends Equatable {
  const BadgeAward({
    required this.id,
    required this.name,
    required this.emoji,
    required this.description,
    this.awardedAt,
  });

  final String id;
  final String name;
  final String emoji;
  final String description;
  final DateTime? awardedAt;

  factory BadgeAward.fromJson(Map<String, dynamic> json) => BadgeAward(
        id: json['id'] as String,
        name: json['name'] as String,
        emoji: json['emoji'] as String,
        description: json['description'] as String,
        awardedAt: json['awarded_at'] != null
            ? DateTime.parse(json['awarded_at'] as String)
            : null,
      );

  @override
  List<Object?> get props => [id, name, emoji, description, awardedAt];
}

class GamificationDelta extends Equatable {
  const GamificationDelta({
    required this.streakCount,
    required this.treeHealthScore,
    required this.treeHealthDelta,
    required this.graceActive,
    required this.badgesAwarded,
  });

  final int streakCount;
  final int treeHealthScore;
  final int treeHealthDelta;
  final bool graceActive;
  final List<BadgeAward> badgesAwarded;

  factory GamificationDelta.fromJson(Map<String, dynamic> json) =>
      GamificationDelta(
        streakCount: json['streak_count'] as int,
        treeHealthScore: json['tree_health_score'] as int,
        treeHealthDelta: json['tree_health_delta'] as int,
        graceActive: json['grace_active'] as bool? ?? false,
        badgesAwarded: (json['badges_awarded'] as List<dynamic>? ?? [])
            .map((e) => BadgeAward.fromJson(e as Map<String, dynamic>))
            .toList(),
      );

  @override
  List<Object?> get props =>
      [streakCount, treeHealthScore, treeHealthDelta, graceActive, badgesAwarded];
}

class CompleteTaskResponse extends Equatable {
  const CompleteTaskResponse({
    required this.task,
    required this.gamificationDelta,
  });

  final Task task;
  final GamificationDelta gamificationDelta;

  factory CompleteTaskResponse.fromJson(Map<String, dynamic> json) =>
      CompleteTaskResponse(
        task: Task.fromJson(json['task'] as Map<String, dynamic>),
        gamificationDelta: GamificationDelta.fromJson(
          json['gamification_delta'] as Map<String, dynamic>,
        ),
      );

  @override
  List<Object?> get props => [task, gamificationDelta];
}

// ──────────────────────────────────────────────
// Request models
// ──────────────────────────────────────────────

class CreateTaskRequest {
  const CreateTaskRequest({
    required this.title,
    required this.priority,
    required this.taskType,
    this.description,
    this.address,
    this.startAt,
    this.endAt,
    this.sortOrder,
    this.rrule,
  });

  final String title;
  final String? description;
  final String? address;
  final TaskPriority priority;
  final TaskType taskType;
  final DateTime? startAt;
  final DateTime? endAt;
  final int? sortOrder;
  final String? rrule;

  Map<String, dynamic> toJson() => {
        'title': title,
        if (description != null) 'description': description,
        if (address != null) 'address': address,
        'priority': priority.value,
        'task_type': taskType.value,
        if (startAt != null) 'start_at': startAt!.toUtc().toIso8601String(),
        if (endAt != null) 'end_at': endAt!.toUtc().toIso8601String(),
        if (sortOrder != null) 'sort_order': sortOrder,
        if (rrule != null) 'rrule': rrule,
      };
}

// ──────────────────────────────────────────────
// Recurring edit scope (CON-002 §3 PATCH/DELETE)
// ──────────────────────────────────────────────

/// Scope for editing or deleting an instance of a recurring task.
/// Sent as the `?scope=` query parameter on PATCH/DELETE.
enum RecurringEditScope {
  thisOnly,
  thisAndFuture;

  String toApiParam() => switch (this) {
        RecurringEditScope.thisOnly => 'this_only',
        RecurringEditScope.thisAndFuture => 'this_and_future',
      };

  String get label => switch (this) {
        RecurringEditScope.thisOnly => 'This task only',
        RecurringEditScope.thisAndFuture => 'This and all future tasks',
      };

  String get subtitle => switch (this) {
        RecurringEditScope.thisOnly => 'Edit just this occurrence',
        RecurringEditScope.thisAndFuture =>
          'Edit this occurrence and all that follow',
      };
}

class UpdateTaskRequest {
  const UpdateTaskRequest({
    this.title,
    this.description,
    this.address,
    this.priority,
    this.taskType,
    this.status,
    this.startAt,
    this.endAt,
    this.sortOrder,
    this.rrule,
  });

  final String? title;
  final String? description;
  final String? address;
  final TaskPriority? priority;
  final TaskType? taskType;
  final TaskStatus? status;
  final DateTime? startAt;
  final DateTime? endAt;
  final int? sortOrder;
  final String? rrule;

  Map<String, dynamic> toJson() => {
        if (title != null) 'title': title,
        if (description != null) 'description': description,
        if (address != null) 'address': address,
        if (priority != null) 'priority': priority!.value,
        if (taskType != null) 'task_type': taskType!.value,
        if (status != null) 'status': status!.value,
        if (startAt != null) 'start_at': startAt!.toUtc().toIso8601String(),
        if (endAt != null) 'end_at': endAt!.toUtc().toIso8601String(),
        if (sortOrder != null) 'sort_order': sortOrder,
        if (rrule != null) 'rrule': rrule,
      };
}

class SortOrderRequest {
  const SortOrderRequest({required this.sortOrder});
  final int sortOrder;
  Map<String, dynamic> toJson() => {'sort_order': sortOrder};
}
