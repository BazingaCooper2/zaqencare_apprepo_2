/// Model for client_final table.
/// Full schema including all columns from the client_final table.
class Client {
  final int id;
  final String? firstName;
  final String? lastName;
  final String? name;
  final String? email;
  final String? gender;
  final String? status;
  final String? phoneMain;
  final String? phoneOther;
  final String? phonePersonal;
  final String? emailPreferred;
  final String? address;
  final String? addressLine2;
  final String? city;
  final String? province;
  final String? zip;
  final String? country;
  final String? county;
  final String? dateOfBirth;
  final String? preferredName;
  final String? ethnicity;
  final String? preferredLanguage;
  final String? externalId;
  final String? guid;
  final String? branchId;
  final String? brn;
  final String? healthCard;
  final String? healthCardVersion;
  final String? risks;
  final String? primaryDiagnosis;
  final String? clientAilmentType;
  final Map<String, dynamic>? medicalNotes;
  final bool? wheelchairUser;
  final bool? hasCatheter;
  final bool? requiresOxygen;
  final String? covidVaccinationStatus;
  final String? serviceType;
  final String? careMgmt;
  final String? individualService;
  final dynamic tasks;
  final String? instructions;
  final String? schedulingPreferences;
  final String? shiftStartTime;
  final String? shiftEndTime;
  final String? startOn;
  final String? terminationDate;
  final String? communicationMethod;
  final String? communicationMethod2;
  final String? emergencyResponseLevel;
  final String? doctor;
  final String? nurse;
  final String? clientCoordinatorName;
  final String? coordinatorNotes;
  final String? patientLocation;
  final String? referral;
  final String? priorityRiskRating;
  final String? signedMedicationAuthorization;
  final String? livingArrangementsOtherOccupants;
  final String? accountingDetails;
  final Map<String, dynamic>? payrollData;
  final String? password;
  final String? imageUrl;
  final List<String>? groups;
  final String? tagsV2;
  final dynamic notes;
  final dynamic emergencyContacts;
  final dynamic progressNotes;
  final dynamic administrativeNotes;
  final double? latitude;
  final double? longitude;
  final List<CarePlan>? carePlans;

  Client({
    required this.id,
    this.firstName,
    this.lastName,
    this.name,
    this.email,
    this.gender,
    this.status,
    this.phoneMain,
    this.phoneOther,
    this.phonePersonal,
    this.emailPreferred,
    this.address,
    this.addressLine2,
    this.city,
    this.province,
    this.zip,
    this.country,
    this.county,
    this.dateOfBirth,
    this.preferredName,
    this.ethnicity,
    this.preferredLanguage,
    this.externalId,
    this.guid,
    this.branchId,
    this.brn,
    this.healthCard,
    this.healthCardVersion,
    this.risks,
    this.primaryDiagnosis,
    this.clientAilmentType,
    this.medicalNotes,
    this.wheelchairUser,
    this.hasCatheter,
    this.requiresOxygen,
    this.covidVaccinationStatus,
    this.serviceType,
    this.careMgmt,
    this.individualService,
    this.tasks,
    this.instructions,
    this.schedulingPreferences,
    this.shiftStartTime,
    this.shiftEndTime,
    this.startOn,
    this.terminationDate,
    this.communicationMethod,
    this.communicationMethod2,
    this.emergencyResponseLevel,
    this.doctor,
    this.nurse,
    this.clientCoordinatorName,
    this.coordinatorNotes,
    this.patientLocation,
    this.referral,
    this.priorityRiskRating,
    this.signedMedicationAuthorization,
    this.livingArrangementsOtherOccupants,
    this.accountingDetails,
    this.payrollData,
    this.password,
    this.imageUrl,
    this.groups,
    this.tagsV2,
    this.notes,
    this.emergencyContacts,
    this.progressNotes,
    this.administrativeNotes,
    this.latitude,
    this.longitude,
    this.carePlans,
  });

  factory Client.fromJson(Map<String, dynamic> json) {
    return Client(
      id: (json['id'] as num?)?.toInt() ?? 0,
      firstName: (json['first_name'] ?? json['firstName'])?.toString(),
      lastName: (json['last_name'] ?? json['lastName'])?.toString(),
      name: json['name']?.toString(),
      email: json['email']?.toString(),
      gender: json['gender']?.toString(),
      status: json['status']?.toString(),
      phoneMain: (json['phone_main'] ?? json['phone'] ?? json['primary_phone'])
          ?.toString(),
      phoneOther: json['phone_other']?.toString(),
      phonePersonal: json['phone_personal']?.toString(),
      emailPreferred: json['email_preferred']?.toString(),
      address: (json['address'] ??
              json['addressLine1'] ??
              json['address_line_1'] ??
              json['full_address'])
          ?.toString(),
      addressLine2: json['address_line2']?.toString(),
      city: json['city']?.toString(),
      province: (json['province'] ?? json['state'])?.toString(),
      zip: (json['zip'] ?? json['zipCode'] ?? json['zip_code'])?.toString(),
      country: json['country']?.toString(),
      county: json['county']?.toString(),
      dateOfBirth: json['date_of_birth']?.toString(),
      preferredName: json['preferred_name']?.toString(),
      ethnicity: json['ethnicity']?.toString(),
      preferredLanguage: json['preferred_language']?.toString(),
      externalId: json['external_id']?.toString(),
      guid: json['guid']?.toString(),
      branchId: json['branch_id']?.toString(),
      brn: json['brn']?.toString(),
      healthCard: json['health_card']?.toString(),
      healthCardVersion: json['health_card_version']?.toString(),
      risks: json['risks']?.toString(),
      primaryDiagnosis: json['primary_diagnosis']?.toString(),
      clientAilmentType: json['client_ailment_type']?.toString(),
      medicalNotes: json['medical_notes'] is Map
          ? Map<String, dynamic>.from(json['medical_notes'])
          : null,
      wheelchairUser: json['wheelchair_user'] as bool?,
      hasCatheter: json['has_catheter'] as bool?,
      requiresOxygen: json['requires_oxygen'] as bool?,
      covidVaccinationStatus: json['covid_vaccination_status']?.toString(),
      serviceType: () {
        // service_type from the DB, or fallback to individual_service / groups
        final st = json['service_type'] ??
            json['individual_service'] ??
            json['groups'] ??
            json['serviceType'];
        if (st == null) return null;
        if (st is List) return st.join(', ');
        return st.toString();
      }(),
      careMgmt: json['care_mgmt']?.toString(),
      individualService: json['individual_service']?.toString(),
      tasks: json['tasks'],
      instructions: json['instructions']?.toString(),
      schedulingPreferences: json['scheduling_preferences']?.toString(),
      shiftStartTime: json['shift_start_time']?.toString(),
      shiftEndTime: json['shift_end_time']?.toString(),
      startOn: json['start_on']?.toString(),
      terminationDate: json['termination_date']?.toString(),
      communicationMethod: json['communication_method']?.toString(),
      communicationMethod2: json['communication_method_2']?.toString(),
      emergencyResponseLevel: json['emergency_response_level']?.toString(),
      doctor: json['doctor']?.toString(),
      nurse: json['nurse']?.toString(),
      clientCoordinatorName: json['client_coordinator_name']?.toString(),
      coordinatorNotes: json['coordinator_notes']?.toString(),
      patientLocation: json['patient_location']?.toString(),
      referral: json['referral']?.toString(),
      priorityRiskRating: json['priority_risk_rating']?.toString(),
      signedMedicationAuthorization:
          json['signed_medication_authorization']?.toString(),
      livingArrangementsOtherOccupants:
          json['living_arrangements_other_occupants']?.toString(),
      accountingDetails: json['accounting_details']?.toString(),
      payrollData: json['payroll_data'] is Map
          ? Map<String, dynamic>.from(json['payroll_data'])
          : null,
      password: json['password']?.toString(),
      imageUrl: (json['image_url'] ?? json['imageUrl'] ?? json['photo_url'])
          ?.toString(),
      groups: json['groups'] is List
          ? List<String>.from((json['groups'] as List).map((e) => e.toString()))
          : null,
      tagsV2: json['tags_v2']?.toString(),
      notes: json['notes'],
      emergencyContacts: json['emergency_contacts'],
      progressNotes: json['progress_notes'],
      administrativeNotes: json['administrative_notes'],
      latitude: json['latitude'] != null ? (json['latitude'] as num).toDouble() : null,
      longitude: json['longitude'] != null ? (json['longitude'] as num).toDouble() : null,
      carePlans: (json['care_plans'] as List? ?? [])
          .map((e) => CarePlan.fromJson(e as Map<String, dynamic>))
          .toList(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'first_name': firstName,
      'last_name': lastName,
      'name': name,
      'email': email,
      'gender': gender,
      'status': status,
      'phone_main': phoneMain,
      'phone_other': phoneOther,
      'phone_personal': phonePersonal,
      'email_preferred': emailPreferred,
      'address': address,
      'address_line2': addressLine2,
      'city': city,
      'province': province,
      'zip': zip,
      'country': country,
      'county': county,
      'date_of_birth': dateOfBirth,
      'preferred_name': preferredName,
      'ethnicity': ethnicity,
      'preferred_language': preferredLanguage,
      'external_id': externalId,
      'guid': guid,
      'branch_id': branchId,
      'brn': brn,
      'health_card': healthCard,
      'health_card_version': healthCardVersion,
      'risks': risks,
      'primary_diagnosis': primaryDiagnosis,
      'client_ailment_type': clientAilmentType,
      'medical_notes': medicalNotes,
      'wheelchair_user': wheelchairUser,
      'has_catheter': hasCatheter,
      'requires_oxygen': requiresOxygen,
      'covid_vaccination_status': covidVaccinationStatus,
      'service_type': serviceType,
      'care_mgmt': careMgmt,
      'individual_service': individualService,
      'tasks': tasks,
      'instructions': instructions,
      'scheduling_preferences': schedulingPreferences,
      'shift_start_time': shiftStartTime,
      'shift_end_time': shiftEndTime,
      'start_on': startOn,
      'termination_date': terminationDate,
      'communication_method': communicationMethod,
      'communication_method_2': communicationMethod2,
      'emergency_response_level': emergencyResponseLevel,
      'doctor': doctor,
      'nurse': nurse,
      'client_coordinator_name': clientCoordinatorName,
      'coordinator_notes': coordinatorNotes,
      'patient_location': patientLocation,
      'referral': referral,
      'priority_risk_rating': priorityRiskRating,
      'signed_medication_authorization': signedMedicationAuthorization,
      'living_arrangements_other_occupants': livingArrangementsOtherOccupants,
      'accounting_details': accountingDetails,
      'payroll_data': payrollData,
      'image_url': imageUrl,
      'groups': groups,
      'tags_v2': tagsV2,
      'notes': notes,
      'emergency_contacts': emergencyContacts,
      'progress_notes': progressNotes,
      'administrative_notes': administrativeNotes,
      'latitude': latitude,
      'longitude': longitude,
      'care_plans': carePlans?.map((e) => {
        'care_plan_id': e.carePlanId,
        'care_plan_tasks': e.tasks.map((t) => {
          'task_id': t.taskId,
          'task_name': t.taskName,
        }).toList(),
      }).toList(),
    };
  }

  // Backward compatibility getters
  int get clientId => id;
  String get fullName => name ?? '${firstName ?? ''} ${lastName ?? ''}'.trim();
  String get fullAddress {
    final parts = [address, addressLine2, city, province, zip, country]
        .where((s) => s != null && s.isNotEmpty);
    return parts.isNotEmpty ? parts.join(', ') : (name ?? '');
  }

  // Alias for backward compat (old code used `state`)
  String? get state => province;
}

class CarePlan {
  final int carePlanId;
  final List<CarePlanTask> tasks;

  CarePlan.fromJson(Map<String, dynamic> json)
      : carePlanId = json['care_plan_id'],
        tasks = (json['care_plan_tasks'] as List? ?? [])
            .map((e) => CarePlanTask.fromJson(e as Map<String, dynamic>))
            .toList();
}

class CarePlanTask {
  final int taskId;
  final String taskName;

  CarePlanTask.fromJson(Map<String, dynamic> json)
      : taskId = json['task_id'],
        taskName = json['task_name'] ?? '';
}
