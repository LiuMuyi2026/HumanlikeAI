"""add_chat_messages

Revision ID: b5c2e8f43a17
Revises: a3f7e2d91c04
Create Date: 2026-02-08 16:00:00.000000

"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa


# revision identifiers, used by Alembic.
revision: str = 'b5c2e8f43a17'
down_revision: Union[str, None] = 'a3f7e2d91c04'
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    op.create_table(
        'chat_messages',
        sa.Column('id', sa.String(36), primary_key=True),
        sa.Column(
            'character_id',
            sa.String(36),
            sa.ForeignKey('ai_characters.id', ondelete='CASCADE'),
            nullable=False,
        ),
        sa.Column(
            'user_id',
            sa.String(36),
            sa.ForeignKey('users.id', ondelete='CASCADE'),
            nullable=False,
        ),
        sa.Column('role', sa.String(10), nullable=False),
        sa.Column('content_type', sa.String(20), nullable=False),
        sa.Column('content', sa.Text, nullable=True),
        sa.Column('media_url', sa.String(500), nullable=True),
        sa.Column('emotion', sa.String(30), nullable=True),
        sa.Column('valence', sa.Float, nullable=True),
        sa.Column('arousal', sa.Float, nullable=True),
        sa.Column('intensity', sa.String(10), nullable=True),
        sa.Column(
            'created_at',
            sa.DateTime(timezone=True),
            server_default=sa.func.now(),
        ),
    )
    op.create_index(
        'idx_chat_messages_char_user',
        'chat_messages',
        ['character_id', 'user_id', sa.text('created_at DESC')],
    )


def downgrade() -> None:
    op.drop_index('idx_chat_messages_char_user', table_name='chat_messages')
    op.drop_table('chat_messages')
