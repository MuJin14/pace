import 'package:flutter/material.dart';
import 'package:flutter_ui/utils/pix_adapted_screen.dart';
import 'package:flutter_svg/svg.dart';
import 'package:flutter_ui/custom_widget/CustomWidget_2_2.dart';
import 'package:flutter_ui/utils/pix_extensions.dart';
import 'package:flutter_ui/utils/pix_base64_string.dart';
import 'package:flutter_ui/custom_widget/CustomWidget_2_22.dart';
import 'package:flutter_ui/custom_widget/CustomWidget_2_38.dart';
import 'package:flutter_ui/custom_widget/CustomWidget_2_172.dart';

class Frame_2_1 extends StatefulWidget {

  Frame_2_1({super.key,});
  @override
  State<Frame_2_1> createState() => _Frame_2_1State();
}

class _Frame_2_1State extends State<Frame_2_1> {
  late final ImageProvider _image_dnup2_23 = MemoryImage(imageStr_dnup2_23.decodeBase64Image());
  late final ImageProvider _image_cqzu2_39 = MemoryImage(imageStr_cqzu2_39.decodeBase64Image());
  late final ImageProvider _image_tyje2_123 = MemoryImage(imageStr_tyje2_123.decodeBase64Image());
  late final ImageProvider _image_mvlh2_201 = MemoryImage(imageStr_mvlh2_201.decodeBase64Image());

  @override
  void initState() {
    super.initState();
  
  }


  @override
  Widget build(BuildContext context) {
    ScreenUtil().rootSize = Size(390, 844);
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: MediaQuery.removePadding(
        context: context,
        removeTop: true,
        removeBottom: true,
        child: SizedBox(
            width: 390.w,
            height: 844.h,
            child: ListView(
              children: [
                SingleChildScrollView(
                physics: NeverScrollableScrollPhysics(),
                child: Container(
                  constraints: BoxConstraints(minWidth: 390.w, minHeight: 844.h),
                  decoration: BoxDecoration(color: Color.fromRGBO(253, 249, 245,1),),
                  clipBehavior: Clip.hardEdge,
                  child: Column(
                    key: ValueKey("2:1"),
                    mainAxisAlignment: MainAxisAlignment.start,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      CustomWidget_2_2(),
                      CustomWidget_2_22(),
                      CustomWidget_2_38(),
                      CustomWidget_2_172(),
                    ],),),),
              ],
            )
          )
        
      ),
      
      
    );
  }
}
