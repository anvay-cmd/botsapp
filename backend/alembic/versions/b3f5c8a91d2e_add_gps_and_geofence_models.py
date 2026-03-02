"""Add GPS and geofence models

Revision ID: b3f5c8a91d2e
Revises: aadab4900412
Create Date: 2026-03-02 00:00:00.000000

"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa
from sqlalchemy.dialects import postgresql

# revision identifiers, used by Alembic.
revision: str = 'b3f5c8a91d2e'
down_revision: Union[str, None] = 'aadab4900412'
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    # Create geofences table
    op.create_table('geofences',
        sa.Column('id', postgresql.UUID(as_uuid=True), nullable=False),
        sa.Column('user_id', postgresql.UUID(as_uuid=True), nullable=False),
        sa.Column('name', sa.String(length=255), nullable=False),
        sa.Column('latitude', sa.Float(), nullable=False),
        sa.Column('longitude', sa.Float(), nullable=False),
        sa.Column('radius', sa.Float(), nullable=False),
        sa.Column('is_active', sa.Boolean(), nullable=False, server_default='true'),
        sa.Column('created_at', sa.DateTime(), nullable=False, server_default=sa.text('now()')),
        sa.ForeignKeyConstraint(['user_id'], ['users.id'], ),
        sa.PrimaryKeyConstraint('id')
    )
    op.create_index(op.f('ix_geofences_user_id'), 'geofences', ['user_id'], unique=False)

    # Create geofence_subscriptions table
    op.create_table('geofence_subscriptions',
        sa.Column('id', postgresql.UUID(as_uuid=True), nullable=False),
        sa.Column('fence_id', postgresql.UUID(as_uuid=True), nullable=False),
        sa.Column('chat_id', postgresql.UUID(as_uuid=True), nullable=False),
        sa.Column('event_type', sa.String(length=50), nullable=False),
        sa.Column('created_at', sa.DateTime(), nullable=False, server_default=sa.text('now()')),
        sa.ForeignKeyConstraint(['chat_id'], ['chats.id'], ),
        sa.ForeignKeyConstraint(['fence_id'], ['geofences.id'], ondelete='CASCADE'),
        sa.PrimaryKeyConstraint('id')
    )
    op.create_index(op.f('ix_geofence_subscriptions_fence_id'), 'geofence_subscriptions', ['fence_id'], unique=False)
    op.create_index(op.f('ix_geofence_subscriptions_chat_id'), 'geofence_subscriptions', ['chat_id'], unique=False)

    # Create location_tracking table
    op.create_table('location_tracking',
        sa.Column('id', postgresql.UUID(as_uuid=True), nullable=False),
        sa.Column('user_id', postgresql.UUID(as_uuid=True), nullable=False),
        sa.Column('latitude', sa.Float(), nullable=False),
        sa.Column('longitude', sa.Float(), nullable=False),
        sa.Column('accuracy', sa.Float(), nullable=True),
        sa.Column('altitude', sa.Float(), nullable=True),
        sa.Column('speed', sa.Float(), nullable=True),
        sa.Column('heading', sa.Float(), nullable=True),
        sa.Column('timestamp', sa.DateTime(), nullable=False, server_default=sa.text('now()')),
        sa.ForeignKeyConstraint(['user_id'], ['users.id'], ),
        sa.PrimaryKeyConstraint('id')
    )
    op.create_index(op.f('ix_location_tracking_user_id'), 'location_tracking', ['user_id'], unique=False)
    op.create_index(op.f('ix_location_tracking_timestamp'), 'location_tracking', ['timestamp'], unique=False)


def downgrade() -> None:
    # Drop tables in reverse order
    op.drop_index(op.f('ix_location_tracking_timestamp'), table_name='location_tracking')
    op.drop_index(op.f('ix_location_tracking_user_id'), table_name='location_tracking')
    op.drop_table('location_tracking')

    op.drop_index(op.f('ix_geofence_subscriptions_chat_id'), table_name='geofence_subscriptions')
    op.drop_index(op.f('ix_geofence_subscriptions_fence_id'), table_name='geofence_subscriptions')
    op.drop_table('geofence_subscriptions')

    op.drop_index(op.f('ix_geofences_user_id'), table_name='geofences')
    op.drop_table('geofences')
