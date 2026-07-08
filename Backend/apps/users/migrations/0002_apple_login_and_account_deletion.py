# Generated manually — Apple Sign-In login_type + account-deletion timestamp

from django.db import migrations, models


class Migration(migrations.Migration):

    dependencies = [
        ('users', '0001_initial'),
    ]

    operations = [
        migrations.AlterField(
            model_name='user',
            name='login_type',
            field=models.CharField(
                choices=[
                    ('phone', 'Phone'),
                    ('otp', 'OTP'),
                    ('google', 'Google'),
                    ('facebook', 'Facebook'),
                    ('apple', 'Apple'),
                    ('biometric', 'Biometric'),
                ],
                default='phone',
                max_length=20,
            ),
        ),
        migrations.AddField(
            model_name='user',
            name='deleted_at',
            field=models.DateTimeField(blank=True, null=True),
        ),
    ]
