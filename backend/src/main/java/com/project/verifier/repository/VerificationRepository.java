package com.project.verifier.repository;

import com.project.verifier.entity.VerificationRecord;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.stereotype.Repository;

import java.util.Optional;
import java.util.UUID;

@Repository
public interface VerificationRepository extends JpaRepository<VerificationRecord, UUID> {
    Optional<VerificationRecord> findByMediaUrl(String mediaUrl);
}
