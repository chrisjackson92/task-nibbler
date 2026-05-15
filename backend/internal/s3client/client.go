package s3client

import (
	"context"
	"fmt"
	"time"

	"github.com/aws/aws-sdk-go-v2/aws"
	awsconfig "github.com/aws/aws-sdk-go-v2/config"
	"github.com/aws/aws-sdk-go-v2/credentials"
	"github.com/aws/aws-sdk-go-v2/service/s3"
)

// ────────────────────────────────────────────────────────────────────────────
// Client interface — enables mock injection in attachment service tests
// ────────────────────────────────────────────────────────────────────────────

// Client is the interface used by AttachmentService.
// The concrete awsS3Client satisfies it; tests inject a mock.
type Client interface {
	// PresignPutURL returns a presigned PUT URL for the client to upload directly to S3.
	// TTL must be 15 minutes per CON-002 §4.
	PresignPutURL(ctx context.Context, key, mimeType string, ttl time.Duration) (url string, expiresAt time.Time, err error)

	// PresignGetURL returns a presigned GET URL for the client to download from S3.
	// TTL must be 60 minutes per CON-002 §4.
	PresignGetURL(ctx context.Context, key string, ttl time.Duration) (url string, expiresAt time.Time, err error)

	// DeleteObject deletes a single S3 object. Called synchronously before DB DELETE
	// per the audit checklist (AUD audit: S3 delete before DB delete).
	DeleteObject(ctx context.Context, key string) error
}

// ────────────────────────────────────────────────────────────────────────────
// Config
// ────────────────────────────────────────────────────────────────────────────

// Config holds S3 connection parameters read from environment variables.
type Config struct {
	AccessKeyID     string
	SecretAccessKey string
	Region          string
	Bucket          string
}

// ────────────────────────────────────────────────────────────────────────────
// Concrete implementation
// ────────────────────────────────────────────────────────────────────────────

type awsS3Client struct {
	client  *s3.Client
	presign *s3.PresignClient
	bucket  string
}

// New creates a production S3 client from explicit credentials (not instance profile).
// Credentials come from environment variables via the Config struct.
func New(ctx context.Context, cfg Config) (Client, error) {
	awsCfg, err := awsconfig.LoadDefaultConfig(ctx,
		awsconfig.WithRegion(cfg.Region),
		awsconfig.WithCredentialsProvider(credentials.NewStaticCredentialsProvider(
			cfg.AccessKeyID,
			cfg.SecretAccessKey,
			"",
		)),
	)
	if err != nil {
		return nil, fmt.Errorf("s3client.New: load aws config: %w", err)
	}

	s3c := s3.NewFromConfig(awsCfg)
	return &awsS3Client{
		client:  s3c,
		presign: s3.NewPresignClient(s3c),
		bucket:  cfg.Bucket,
	}, nil
}

// PresignPutURL returns a presigned S3 PUT URL with the given Content-Type locked.
func (c *awsS3Client) PresignPutURL(ctx context.Context, key, mimeType string, ttl time.Duration) (string, time.Time, error) {
	req, err := c.presign.PresignPutObject(ctx, &s3.PutObjectInput{
		Bucket:      aws.String(c.bucket),
		Key:         aws.String(key),
		ContentType: aws.String(mimeType), // Content-Type is locked to declared MIME type
	}, func(opts *s3.PresignOptions) {
		opts.Expires = ttl
	})
	if err != nil {
		return "", time.Time{}, fmt.Errorf("s3client.PresignPutURL: %w", err)
	}
	expiresAt := time.Now().UTC().Add(ttl)
	return req.URL, expiresAt, nil
}

// PresignGetURL returns a presigned S3 GET URL.
func (c *awsS3Client) PresignGetURL(ctx context.Context, key string, ttl time.Duration) (string, time.Time, error) {
	req, err := c.presign.PresignGetObject(ctx, &s3.GetObjectInput{
		Bucket: aws.String(c.bucket),
		Key:    aws.String(key),
	}, func(opts *s3.PresignOptions) {
		opts.Expires = ttl
	})
	if err != nil {
		return "", time.Time{}, fmt.Errorf("s3client.PresignGetURL: %w", err)
	}
	expiresAt := time.Now().UTC().Add(ttl)
	return req.URL, expiresAt, nil
}

// DeleteObject deletes a single S3 object by key.
func (c *awsS3Client) DeleteObject(ctx context.Context, key string) error {
	_, err := c.client.DeleteObject(ctx, &s3.DeleteObjectInput{
		Bucket: aws.String(c.bucket),
		Key:    aws.String(key),
	})
	if err != nil {
		return fmt.Errorf("s3client.DeleteObject key=%s: %w", key, err)
	}
	return nil
}
