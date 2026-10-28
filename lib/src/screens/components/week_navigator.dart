import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

class WeekNavigator extends StatefulWidget {
  final DateTime? date;
  final Function? onDateChange;

  const WeekNavigator({super.key, this.date, this.onDateChange});

  @override
  State<WeekNavigator> createState() => _WeekNavigatorState();
}

class _WeekNavigatorState extends State<WeekNavigator> {
  DateTime selectedDate = DateTime.now(); // Initial Date
  DateTime weekStartDate = DateTime(2025, 2, 4); // Start of the di

  @override
  void initState() {
    super.initState();
    selectedDate = widget.date ?? DateTime.now();
    _adjustToWeekStart();
  }

  Future<void> _pickDate(BuildContext context) async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: selectedDate,
      firstDate: DateTime(1000),
      lastDate: DateTime(3000),
    );

    if (picked != null && picked != selectedDate) {
      setState(() {
        _selectDay(picked);
        _adjustToWeekStart();
      });
    }
  }

  void _adjustToWeekStart() {
    setState(() {
      // Ensure week starts on Monday
      weekStartDate =
          selectedDate.subtract(Duration(days: selectedDate.weekday - 1));
    });
  }

  void _changeWeek(int days) {
    setState(() {
      weekStartDate = weekStartDate.add(Duration(days: days));
      // selectedDate = weekStartDate; // Default to the first day of the new week
    });
  }

  void _selectDay(DateTime date) {
    setState(() {
      selectedDate = date;
    });
    widget.onDateChange?.call(selectedDate);
  }

  bool isSameDay(DateTime date1, DateTime date2) {
    return date1.year == date2.year &&
        date1.month == date2.month &&
        date1.day == date2.day;
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      // mainAxisAlignment: MainAxisAlignment.center,
      // mainAxisSize: MainAxisSize.max,
      children: [
        SizedBox(
          height: 20,
        ),
        // Week Navigation Row
        Container(
            // color: Colors.yellow,
            child: Align(
              // alignment: Alignment.center,
              widthFactor: 1.0,
              child: Container(
                  // color: Colors.lightBlueAccent,
                  width: 400,
                  child: Row(
                    mainAxisSize: MainAxisSize.max,
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    // crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SizedBox(width: 60, child: Text(
                        "${DateFormat('MMM, y').format(weekStartDate)}",
                        style: TextStyle(
                            fontSize: 12, fontWeight: FontWeight.w500),
                      )),
                      // SizedBox(
                      //   width: 5,
                      // ),
                      GestureDetector(
                        onTap: () {
                          _pickDate(context);

                        },
                        child: Card(
                            child: Container(
                          padding:
                              EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                          child: Row(
                            // mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.calendar_today, size: 20),
                              SizedBox(width: 5),
                              Text(
                                "${DateFormat('d MMM, y').format(selectedDate)}",
                                style: TextStyle(
                                    fontSize: 14, fontWeight: FontWeight.bold),
                              ),
                            ],
                          ),
                        )),
                      ),

                      SizedBox(
                          width: 60,
                          height: 30,
                          child: !isSameDay(selectedDate, DateTime.now())
                              ? IconButton(
                                  iconSize: 20,
                                  icon: Icon(Icons.refresh),
                                  onPressed: () {
                                    _selectDay(DateTime.now());
                                    _adjustToWeekStart();
                                  }, // Move to previous week
                                )
                              : Container()),
                    ],
                  )),
            )),

        SizedBox(height: 10),
        // Weekdays Row
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            IconButton(
              iconSize: 50,
              icon: Icon(Icons.arrow_left),
              onPressed: () => _changeWeek(-7), // Move to previous week
            ),
            ...List.generate(7, (index) {
              DateTime day = weekStartDate.add(Duration(days: index));
              bool isSelected = day.isAtSameMomentAs(selectedDate);
              return GestureDetector(
                onTap: () => _selectDay(day),
                child: Container(
                  width: 50,
                  padding: EdgeInsets.symmetric(vertical: 10, horizontal: 12),
                  margin: EdgeInsets.symmetric(horizontal: 4),
                  decoration: BoxDecoration(
                    color: isSelected ? Colors.blue : Colors.grey[200],
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Column(
                    children: [
                      Text(
                        DateFormat.E('de_DE').format(day), // Mon, Tue, etc.
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: isSelected ? Colors.white : Colors.black,
                        ),
                      ),
                      SizedBox(height: 4),
                      Text(
                        DateFormat.d().format(day), // Day number
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: isSelected ? Colors.white : Colors.black,
                        ),
                      ),
                    ],
                  ),
                ),
              );
            }),
            IconButton(
              iconSize: 50,
              icon: Icon(Icons.arrow_right),
              onPressed: () => _changeWeek(7), // Move to next week
            ),
          ],
        ),
      ],
    );
  }
}
