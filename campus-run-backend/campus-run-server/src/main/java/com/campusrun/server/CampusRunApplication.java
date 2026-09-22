package com.campusrun.server;

import org.springframework.boot.SpringApplication;
import org.springframework.boot.autoconfigure.SpringBootApplication;

@SpringBootApplication(scanBasePackages = "com.campusrun")
public class CampusRunApplication {

    public static void main(String[] args) {
        SpringApplication.run(CampusRunApplication.class, args);
    }
}
