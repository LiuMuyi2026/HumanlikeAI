"""add_character_emotion_images

Revision ID: a3f7e2d91c04
Revises: 01b111d5ae14
Create Date: 2026-02-08 12:00:00.000000

"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa


# revision identifiers, used by Alembic.
revision: str = 'a3f7e2d91c04'
down_revision: Union[str, None] = '01b111d5ae14'
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    op.create_table(
        'character_emotion_images',
        sa.Column('id', sa.String(36), primary_key=True),
        sa.Column(
            'character_id',
            sa.String(36),
            sa.ForeignKey('ai_characters.id', ondelete='CASCADE'),
            nullable=False,
            index=True,
        ),
        sa.Column('emotion_key', sa.String(30), nullable=False),
        sa.Column('image_path', sa.String(500), nullable=False),
        sa.Column('prompt_used', sa.Text, nullable=True),
        sa.Column(
            'created_at',
            sa.DateTime(timezone=True),
            server_default=sa.func.now(),
        ),
        sa.UniqueConstraint('character_id', 'emotion_key', name='uq_char_emotion_key'),
    )


def downgrade() -> None:
    op.drop_table('character_emotion_images')
