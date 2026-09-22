package com.campusrun.server;

import org.springframework.boot.SpringApplication;
import org.springframework.boot.autoconfigure.SpringBootApplication;
import org.springframework.scheduling.annotation.EnableScheduling;

@SpringBootApplication(scanBasePackages = "com.campusrun")
@EnableScheduling
public class CampusRunApplication {

    public static void main(String[] args) {
        SpringApplication.run(CampusRunApplication.class, args);
    }
}
