class Employee {
  final int empId;
  final String firstName;
  final String lastName;
  final String? email;
  final String? phone;
  final String? designation;
  final String? address;
  final String? status; // Dart field kept as 'status' for backward compat;
  //                       mapped from DB column 'Employee_status'
  final String? skills;
  final String? qualifications;
  final String? imageUrl;

  Employee({
    required this.empId,
    required this.firstName,
    required this.lastName,
    this.email,
    this.phone,
    this.designation,
    this.address,
    this.status,
    this.skills,
    this.qualifications,
    this.imageUrl,
  });

  factory Employee.fromJson(Map<String, dynamic> json) {
    // emp_id: DB type changed bigint → integer; handle both num types safely.
    final rawEmpId = json['emp_id'];
    final empId = rawEmpId is num ? rawEmpId.toInt() : 0;

    // 'status' column was renamed to 'Employee_status' in employee_final.
    // Accept both keys so the model still works if old data is ever encountered.
    final status = (json['Employee_status'] ?? json['status']) as String?;

    return Employee(
      empId: empId,
      firstName: json['first_name'] as String? ?? '',
      lastName: json['last_name'] as String? ?? '',
      email: json['email'] as String?,
      phone: json['phone'] as String?,
      designation: json['designation'] as String?,
      address: json['address'] as String?,
      status: status,
      skills: json['skills'] as String?,
      qualifications: json['qualifications'] as String?,
      imageUrl: json['image_url'] as String?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'emp_id': empId,
      'first_name': firstName,
      'last_name': lastName,
      'email': email,
      'phone': phone,
      'designation': designation,
      'address': address,
      // Write back using the new column name.
      'Employee_status': status,
      'skills': skills,
      'qualifications': qualifications,
      'image_url': imageUrl,
    };
  }

  String get fullName => '$firstName $lastName';
}
