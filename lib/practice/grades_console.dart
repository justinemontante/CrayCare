import 'dart:io';

class StudentGrade {
  String name;
  double midtermGrade;
  double finalGrade;

  StudentGrade(this.name, this.midtermGrade, this.finalGrade);

  double getAverage() {
    return (midtermGrade + finalGrade) / 2;
  }

  String getRemarks() {
    if (getAverage() >= 75) {
      return "PASSED";
    } else {
      return "FAILED";
    }
  }
}

void main() {
  StudentGrade studentA = StudentGrade("Justine", 74, 74);

  print(studentA.name);
  print(studentA.getAverage());
  print(studentA.getRemarks());
}
